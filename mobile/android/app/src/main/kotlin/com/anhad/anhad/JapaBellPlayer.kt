package com.anhad.anhad

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.SoundPool

/**
 * Plays the japa completion sounds (docs/ONBOARDING.md §5 item 1) — a
 * process-wide singleton so MainActivity (foreground, no screen-off
 * session active) and JapaForegroundService (screen-off session, which may
 * outlive the Activity) share one preloaded SoundPool rather than each
 * keeping its own copy in memory.
 *
 * Deliberately SoundPool, not MediaPlayer or Flutter's just_audio:
 * SoundPool is built for exactly this — a short sound effect, decoded in
 * memory, played with minimal latency — and critically, it never requests
 * audio focus the way MediaPlayer/ExoPlayer do by default. Paired with
 * AudioAttributes.USAGE_ASSISTANCE_SONIFICATION below, that's what lets
 * the bell mix with whatever the user is already playing (a bhajan,
 * music) instead of pausing it.
 *
 * Every play() call re-checks the current audio output route — headphones/
 * Bluetooth/USB only, never the built-in speaker or earpiece, regardless
 * of whether a screen-off session is active — since a device can be
 * connected or disconnected between session start and any given
 * completion, and devotional practice in public shouldn't announce
 * itself.
 */
object JapaBellPlayer {

    enum class CompletionKind { ROUND, TARGET }

    private const val PREFS_NAME = "japa_bell_prefs"
    private const val PREF_HEADPHONE_HINT_PENDING = "headphone_hint_pending"
    private const val PREF_HEADPHONE_HINT_SHOWN = "headphone_hint_shown"

    private var soundPool: SoundPool? = null
    private var roundSoundId = 0
    private var targetSoundId = 0
    private var roundLoaded = false
    private var targetLoaded = false

    /**
     * Loads both sounds into memory — idempotent, safe to call from both
     * MainActivity.configureFlutterEngine and the service's ACTION_START,
     * whichever happens first for a given process lifetime. "Preload and
     * decode at session start, not on the completing bead."
     */
    fun preload(context: Context) {
        if (soundPool != null) return

        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val pool = SoundPool.Builder()
            .setAudioAttributes(attributes)
            .setMaxStreams(2)
            .build()
        pool.setOnLoadCompleteListener { _, sampleId, status ->
            if (status != 0) return@setOnLoadCompleteListener
            when (sampleId) {
                roundSoundId -> roundLoaded = true
                targetSoundId -> targetLoaded = true
            }
        }

        val appContext = context.applicationContext
        roundSoundId = pool.load(appContext, R.raw.japa_round, 1)
        targetSoundId = pool.load(appContext, R.raw.japa_target, 1)
        soundPool = pool
    }

    /**
     * Which sound (if any) firing between [oldCount] and [newCount] should
     * play, given [malaLength] — target takes priority over round when
     * they coincide (malaLength == 108: "round and target coincide, one
     * strike," not two layered sounds). Checked as "crossed a multiple"
     * rather than newCount % x == 0 so a multi-tap jump between two checks
     * still fires correctly instead of silently skipping the sound.
     */
    fun completionKind(oldCount: Int, newCount: Int, malaLength: Int): CompletionKind? {
        if (newCount <= oldCount || malaLength <= 0) return null
        val ringLength = minOf(malaLength, 108)
        val crossedTarget = newCount / malaLength > oldCount / malaLength
        if (crossedTarget) return CompletionKind.TARGET
        val crossedRing = newCount / ringLength > oldCount / ringLength
        if (crossedRing) return CompletionKind.ROUND
        return null
    }

    /**
     * Plays [kind] if audio is currently routed to a headphone/Bluetooth/
     * USB output — never the speaker or earpiece. Returns whether it
     * actually played; a false return (route not eligible) is what drives
     * the one-time headphone hint, not a guess about what "should" have
     * happened.
     */
    fun play(context: Context, kind: CompletionKind): Boolean {
        if (!isHeadphoneOrBluetoothRouted(context)) {
            markHeadphoneHintPendingIfNeverShown(context)
            return false
        }
        val pool = soundPool ?: return false
        val loaded = if (kind == CompletionKind.ROUND) roundLoaded else targetLoaded
        if (!loaded) return false // still decoding — shouldn't happen given preload timing, but never crash on it
        val id = if (kind == CompletionKind.ROUND) roundSoundId else targetSoundId
        pool.play(id, 1f, 1f, /* priority = */ 1, /* loop = */ 0, /* rate = */ 1f)
        return true
    }

    /**
     * True once — the first time [play] is called with no pending
     * suppression already recorded. MainActivity surfaces this as a
     * dismissible message; consuming it also marks the hint as shown for
     * good, so it truly only appears once ever, not once per suppressed
     * play.
     */
    fun consumePendingHeadphoneHint(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val pending = prefs.getBoolean(PREF_HEADPHONE_HINT_PENDING, false)
        if (pending) {
            prefs.edit()
                .putBoolean(PREF_HEADPHONE_HINT_PENDING, false)
                .putBoolean(PREF_HEADPHONE_HINT_SHOWN, true)
                .apply()
        }
        return pending
    }

    private fun markHeadphoneHintPendingIfNeverShown(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (prefs.getBoolean(PREF_HEADPHONE_HINT_SHOWN, false)) return
        prefs.edit().putBoolean(PREF_HEADPHONE_HINT_PENDING, true).apply()
    }

    private fun isHeadphoneOrBluetoothRouted(context: Context): Boolean {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        val routedTypes = setOf(
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_HEARING_AID,
        )
        return devices.any { it.type in routedTypes }
    }
}
