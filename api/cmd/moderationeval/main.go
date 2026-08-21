// Command moderationeval runs every file under testdata/<class>/*.mp4
// through the real moderation pipeline (internal/moderation) — the exact
// same code path RunAndSave uses in production, not a parallel
// reimplementation — and reports accuracy.
//
// testdata/bhajan/ and testdata/filmi/ are scored strictly: bhajan/ expects
// the pipeline to reach APPROVED (a miss is a false negative — real
// devotional content wrongly held), filmi/ expects anything other than
// APPROVED (a miss is a false positive — commercial content wrongly
// auto-published, the dangerous direction). testdata/hard/ has no single
// correct answer per docs/PRD.md §8.3's gray-zone policy and the
// instrumental gap docs/GAPS.md flags, so it's reported descriptively —
// what the pipeline decided and why — not scored pass/fail.
//
// Usage:
//
//	go run ./cmd/moderationeval [-dir testdata] [-concurrency 2]
//
// Reads the same TRANSCRIBER_BACKEND/CLASSIFIER_BACKEND/FINGERPRINT_BACKEND
// env vars as cmd/api, so running once with CLASSIFIER_BACKEND=keyword
// sanity-checks the pipeline's plumbing, and again with
// CLASSIFIER_BACKEND=claude produces the real accuracy numbers.
package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/anhad/api/internal/config"
	"github.com/anhad/api/internal/moderation"
)

type fileResult struct {
	Class    string // the testdata/ subfolder this file came from
	Path     string
	Result   *moderation.PipelineResult
	Err      error
	Duration time.Duration
}

func main() {
	dir := flag.String("dir", "testdata", "root directory with one subfolder per class")
	concurrency := flag.Int("concurrency", 2, "how many files to process in parallel (CPU-bound — see worker.go's own Concurrency)")
	cacheDir := flag.String("cache-dir", filepath.Join(os.TempDir(), "anhad-moderationeval-cache"),
		"cache transcripts here, keyed by absolute file path — transcription is the slow, classifier-independent part of a run, "+
			"so a classifier-only retry (new key, topped-up credits, a prompt tweak) doesn't have to redo it")
	flag.Parse()

	logger := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelWarn}))

	cfg, err := config.Load()
	if err != nil {
		fmt.Fprintf(os.Stderr, "load config: %v\n", err)
		os.Exit(1)
	}
	pipeline, err := moderation.BuildPipeline(cfg, logger)
	if err != nil {
		fmt.Fprintf(os.Stderr, "build pipeline: %v\n", err)
		os.Exit(1)
	}
	if err := os.MkdirAll(*cacheDir, 0o755); err != nil {
		fmt.Fprintf(os.Stderr, "create cache dir: %v\n", err)
		os.Exit(1)
	}
	modelKeyPart := cfg.TranscriberBackend
	switch cfg.TranscriberBackend {
	case "local":
		modelKeyPart += ":" + cfg.WhisperModelPath
	case "openai":
		modelKeyPart += ":whisper-1"
	}
	pipeline.Transcriber = &cachingTranscriber{inner: pipeline.Transcriber, cacheDir: *cacheDir, modelKeyPart: modelKeyPart}
	fmt.Fprintf(os.Stderr,
		"pipeline: transcriber=%s classifier=%s fingerprint=%s (transcript cache: %s)\n\n",
		cfg.TranscriberBackend, cfg.ClassifierBackend, cfg.FingerprintBackend, *cacheDir,
	)

	files, err := discoverTestFiles(*dir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "discover test files: %v\n", err)
		os.Exit(1)
	}
	if len(files) == 0 {
		fmt.Fprintf(os.Stderr, "no files found under %s/<class>/\n", *dir)
		os.Exit(1)
	}

	results := runAll(pipeline, files, *concurrency)
	sort.Slice(results, func(i, j int) bool {
		if results[i].Class != results[j].Class {
			return results[i].Class < results[j].Class
		}
		return results[i].Path < results[j].Path
	})

	printPerFile(results)
	printScored(results, "bhajan", "APPROVED")
	printScored(results, "filmi", "NOT APPROVED")
	printHard(results)
}

func discoverTestFiles(root string) ([]fileResult, error) {
	entries, err := os.ReadDir(root)
	if err != nil {
		return nil, err
	}
	var files []fileResult
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		class := e.Name()
		classDir := filepath.Join(root, class)
		classFiles, err := os.ReadDir(classDir)
		if err != nil {
			return nil, err
		}
		for _, f := range classFiles {
			if f.IsDir() || strings.HasPrefix(f.Name(), ".") {
				continue
			}
			files = append(files, fileResult{Class: class, Path: filepath.Join(classDir, f.Name())})
		}
	}
	return files, nil
}

func runAll(pipeline *moderation.Pipeline, files []fileResult, concurrency int) []fileResult {
	jobs := make(chan int, len(files))
	for i := range files {
		jobs <- i
	}
	close(jobs)

	var wg sync.WaitGroup
	var mu sync.Mutex
	done := 0

	for w := 0; w < concurrency; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := range jobs {
				start := time.Now()
				ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
				ctx = context.WithValue(ctx, cacheKeyContextKey{}, files[i].Path)
				result, err := pipeline.Run(ctx, files[i].Path)
				cancel()

				files[i].Result = result
				files[i].Err = err
				files[i].Duration = time.Since(start)

				mu.Lock()
				done++
				fmt.Fprintf(os.Stderr, "[%d/%d] %s/%s (%s)\n",
					done, len(files), files[i].Class, filepath.Base(files[i].Path), files[i].Duration.Round(time.Second))
				mu.Unlock()
			}
		}()
	}
	wg.Wait()
	return files
}

func printPerFile(results []fileResult) {
	fmt.Println("=== per-file results ===")
	for _, r := range results {
		name := filepath.Base(r.Path)
		if r.Err != nil {
			fmt.Printf("%-8s %-45s ERROR: %v\n", r.Class, name, r.Err)
			continue
		}
		label := string(r.Result.ClassifierLabel)
		if label == "" {
			label = "-"
		}
		fp := ""
		if r.Result.FingerprintMatched {
			fp = " fingerprint-match:" + r.Result.FingerprintTrack
		}
		fmt.Printf("%-8s %-45s -> %-8s (classifier: %s)%s\n", r.Class, name, strings.ToUpper(r.Result.Status), label, fp)
	}
	fmt.Println()
}

// printScored computes false-positive/false-negative rates for one class
// against its single expected outcome. wantOutcome is either "APPROVED"
// (bhajan/ — a miss is a false negative) or "NOT APPROVED" (filmi/ — a
// miss is a false positive, the dangerous direction: commercial content
// wrongly auto-published).
func printScored(results []fileResult, class, wantOutcome string) {
	var total, correct, missed, errored int
	var missedFiles []string
	for _, r := range results {
		if r.Class != class {
			continue
		}
		total++
		if r.Err != nil {
			errored++
			missedFiles = append(missedFiles, filepath.Base(r.Path)+" (error: "+r.Err.Error()+")")
			continue
		}
		got := strings.ToUpper(r.Result.Status)
		isMatch := (wantOutcome == "APPROVED" && got == "APPROVED") ||
			(wantOutcome == "NOT APPROVED" && got != "APPROVED")
		if isMatch {
			correct++
		} else {
			missed++
			missedFiles = append(missedFiles, fmt.Sprintf("%s (got %s)", filepath.Base(r.Path), got))
		}
	}

	kind := "false negative rate"
	if wantOutcome == "NOT APPROVED" {
		kind = "false positive rate"
	}
	rate := 0.0
	if total > 0 {
		rate = float64(missed+errored) / float64(total) * 100
	}
	fmt.Printf("=== %s/ (expect %s): %d/%d correct, %s = %.1f%% ===\n", class, wantOutcome, correct, total, kind, rate)
	for _, f := range missedFiles {
		fmt.Printf("  MISS: %s\n", f)
	}
	fmt.Println()
}

// printHard reports testdata/hard/ descriptively rather than scored —
// there's no single correct answer to check each file against (see this
// file's own top-of-file doc), so this is deliberately just "what did the
// pipeline decide, and why," for a human to judge.
func printHard(results []fileResult) {
	fmt.Println("=== hard/ (descriptive — no single correct answer, judge manually) ===")
	for _, r := range results {
		if r.Class != "hard" {
			continue
		}
		name := filepath.Base(r.Path)
		if r.Err != nil {
			fmt.Printf("  %-45s ERROR: %v\n", name, r.Err)
			continue
		}
		reason := r.Result.ClassifierReason
		if r.Result.FingerprintMatched {
			reason = fmt.Sprintf("fingerprint matched %q; %s", r.Result.FingerprintTrack, reason)
		}
		transcriptPreview := r.Result.Transcript
		if len(transcriptPreview) > 80 {
			transcriptPreview = transcriptPreview[:80] + "…"
		}
		fmt.Printf("  %-45s -> %-8s (%s)\n    transcript: %q\n    reason: %s\n\n",
			name, strings.ToUpper(r.Result.Status), r.Result.ClassifierLabel, transcriptPreview, reason)
	}
}

// cachingTranscriber wraps the real Transcriber with a disk cache keyed on
// the absolute file path *and* which model/backend produced the
// transcript, so a rerun that only changes the classifier (a new API key,
// topped-up credits, a prompt tweak) skips the slow part — transcription —
// entirely for files it's already seen, while switching TRANSCRIBER_BACKEND
// or WHISPER_MODEL_PATH naturally misses the cache instead of silently
// serving a stale transcript from a different model. Eval-only: the
// production pipeline (worker.go) has no equivalent, since a real upload
// is only ever transcribed once anyway.
type cachingTranscriber struct {
	inner        moderation.Transcriber
	cacheDir     string
	modelKeyPart string
}

func (c *cachingTranscriber) Transcribe(ctx context.Context, wavPath string) (*moderation.Transcript, error) {
	// Keyed on wavPath, which is a fresh temp file per call
	// (moderation.ExtractAudio) — the cache key that actually matters is
	// the *source* file, so runAll passes that through via the context
	// instead of wavPath itself.
	key, _ := ctx.Value(cacheKeyContextKey{}).(string)
	if key == "" {
		return c.inner.Transcribe(ctx, wavPath)
	}
	key = c.modelKeyPart + "|" + key

	cachePath := filepath.Join(c.cacheDir, cacheFileName(key))
	if data, err := os.ReadFile(cachePath); err == nil {
		var cached moderation.Transcript
		if json.Unmarshal(data, &cached) == nil {
			return &cached, nil
		}
	}

	transcript, err := c.inner.Transcribe(ctx, wavPath)
	if err != nil {
		return nil, err
	}
	if data, err := json.Marshal(transcript); err == nil {
		_ = os.WriteFile(cachePath, data, 0o644)
	}
	return transcript, nil
}

type cacheKeyContextKey struct{}

func cacheFileName(sourcePath string) string {
	sum := sha256.Sum256([]byte(sourcePath))
	return hex.EncodeToString(sum[:]) + ".json"
}
