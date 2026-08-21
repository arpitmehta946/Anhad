package moderation

import (
	"context"
	"fmt"
	"os"
	"os/exec"
)

// ExtractAudio pulls a 16kHz mono WAV out of videoPath via ffmpeg — the
// format both whisper.cpp and (once wired) ACRCloud's fingerprint tooling
// expect, and small enough not to matter for a background job. Writes to a
// fresh temp file and returns its path; the caller is responsible for
// removing it once done (RunPipeline does this in a defer).
func ExtractAudio(ctx context.Context, ffmpegPath, videoPath string) (string, error) {
	out, err := os.CreateTemp("", "anhad-mod-audio-*.wav")
	if err != nil {
		return "", fmt.Errorf("create temp wav: %w", err)
	}
	outPath := out.Name()
	out.Close()

	cmd := exec.CommandContext(ctx, ffmpegPath,
		"-y", // overwrite the empty temp file ffmpeg otherwise refuses to touch
		"-i", videoPath,
		"-vn", // no video stream — audio only
		"-ar", "16000",
		"-ac", "1",
		"-c:a", "pcm_s16le",
		outPath,
	)
	output, err := cmd.CombinedOutput()
	if err != nil {
		os.Remove(outPath)
		return "", fmt.Errorf("ffmpeg extract audio: %w: %s", err, truncate(string(output), 2000))
	}
	return outPath, nil
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[len(s)-n:] // the useful error detail is usually at the end
}
