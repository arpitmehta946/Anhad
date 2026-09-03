package audio

import "context"

// AudioSource is where an audio_library row's playable audio actually
// comes from once its source reel clears moderation — mirrors
// internal/reels.VideoStorage's own two-implementation shape: a real
// backend (Cloudflare Stream can already serve a video's audio-only track,
// or R2 could hold a genuinely separate extracted file — not built, no
// account to verify either against) and LocalAudioSource, today's default,
// which does no real demuxing at all.
type AudioSource interface {
	// ExtractFromReel returns the URL to store as an audio_library row's
	// r2_url, given its source reel's own video URL.
	ExtractFromReel(ctx context.Context, reelVideoURL string) (audioURL string, err error)
}

// LocalAudioSource is the local-dev stand-in — matches
// internal/reels.LocalVideoStorage's own honesty: not a mock, just not
// real extraction. It hands back the reel's own video URL unchanged; an
// audio player can decode an mp4's audio track directly, which is enough
// to build and verify library browsing and "use this sound" end to end
// with no ffmpeg/Cloudflare dependency. A real backend would instead
// return a distinct, audio-only asset.
type LocalAudioSource struct{}

func NewLocalAudioSource() *LocalAudioSource { return &LocalAudioSource{} }

func (s *LocalAudioSource) ExtractFromReel(ctx context.Context, reelVideoURL string) (string, error) {
	return reelVideoURL, nil
}
