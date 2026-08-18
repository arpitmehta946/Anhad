package com.anhad.anhad

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import androidx.media.VolumeProviderCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Keeps a japa (chant) session alive with the screen off (docs/PRD.md
 * §7.4): the lock-screen-visible notification with pause/end controls
 * (phase 1), volume-key tap capture (phase 2), and getting captured taps
 * into Isar in real time (phase 3, this revision).
 *
 * The capture mechanism is a [MediaSessionCompat] with a remote
 * [VolumeProviderCompat] — when the session is active, Android routes
 * hardware volume-up/down presses to [VolumeProviderCompat.onAdjustVolume]
 * instead of adjusting the system media stream, screen off included, and
 * without needing to actually play any audio. The notification/vibration
 * side of a captured tap is handled natively, right here, and never
 * depends on Dart — with the screen off there's no guarantee the *main*
 * FlutterActivity's engine stays reachable (Android can reclaim a
 * background Activity independently of the foreground service keeping the
 * process alive). Getting the tap into Isar, though, does need Dart —
 * Isar has no native API — so this service runs a second, *headless*
 * FlutterEngine of its own for the duration of a session
 * (japa_background_entrypoint.dart), independent of whatever state the
 * main UI's engine is in. A captured tap updates the notification/vibrates
 * immediately either way; the headless engine call to persist it is
 * best-effort on top, not a dependency for the user-visible part.
 */
class JapaForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "japa_session"
        const val NOTIFICATION_ID = 1001

        const val ACTION_START = "com.anhad.anhad.japa.START"
        const val ACTION_PAUSE = "com.anhad.anhad.japa.PAUSE"
        const val ACTION_RESUME = "com.anhad.anhad.japa.RESUME"
        const val ACTION_END = "com.anhad.anhad.japa.END"
        const val ACTION_UPDATE_COUNT = "com.anhad.anhad.japa.UPDATE_COUNT"
        const val ACTION_UPDATE_SESSION_ID = "com.anhad.anhad.japa.UPDATE_SESSION_ID"
        const val EXTRA_COUNT = "count"
        const val EXTRA_SESSION_ID = "session_id"
        const val EXTRA_CUMULATIVE_BASE = "cumulative_base"

        // Persists which Isar session id is currently being targeted, so
        // MainActivity can answer "is a screen-off session running, and
        // which session is it" (JapaSessionController adopts it on init)
        // without needing a live binding to this service — it may not be
        // running when asked.
        const val PREFS_NAME = "japa_background_prefs"
        const val PREF_ACTIVE_SESSION_ID = "active_session_id"

        // Taps from every row already rotated past this screen-off session
        // (mala completions, connectivity-triggered flushes) — persisted
        // alongside the session id so an unexpected process restart
        // mid-session (a crash, the OS reclaiming memory, anything short of
        // an explicit End) can restore it too. Without this, a restart
        // resets the count JapaSessionController rebuilds its ring/
        // notification total from to whatever's in the currently-adopted
        // row alone, silently dropping everything from rows already
        // rotated past before the restart.
        const val PREF_CUMULATIVE_BASE = "cumulative_base"

        private const val BACKGROUND_ISOLATE_CHANNEL = "com.anhad.anhad/japa_background_isolate"
        private const val BACKGROUND_ENTRYPOINT_LIBRARY =
            "package:anhad/src/features/japa/background/japa_background_entrypoint.dart"
        private const val BACKGROUND_ENTRYPOINT_FUNCTION = "japaBackgroundMain"

        // Local broadcast so MainActivity (when running) can reflect
        // notification-button taps in the Flutter UI without polling.
        const val BROADCAST_STATE_CHANGED = "com.anhad.anhad.japa.STATE_CHANGED"
        const val EXTRA_PAUSED = "paused"
        const val EXTRA_ENDED = "ended"

        // Broadcast on every volume-key tap captured — best-effort only;
        // MainActivity relays it to Dart if (and only if) the main engine
        // happens to be alive and reachable. Nothing depends on this for
        // correctness — see the class doc.
        const val BROADCAST_TAP_CAPTURED = "com.anhad.anhad.japa.TAP_CAPTURED"
        const val EXTRA_TAP_COUNT = "tap_count"

        // A gentle ~30ms tick — long enough to feel, short enough not to
        // read as a system alert. Matches the on-screen tap's
        // HapticFeedback.lightImpact() (japa_screen.dart) in weight.
        private const val TAP_VIBRATION_MS = 30L

        // How often to re-assert the MediaSession as active while a
        // session is running. There's no public API to observe "did
        // Android just hand volume-key routing to something else" (a
        // system sound, another app's session, the lock screen), so this
        // is a defensive, timing-based mitigation rather than a targeted
        // fix for a specific confirmed trigger — observed on-device:
        // volume-key taps silently stopped registering (notification
        // showed no change) until the session was manually stopped and
        // restarted, which suggests we'd lost routing priority.
        // Periodically re-claiming it is the standard approach for this
        // class of Android media-session flakiness.
        private const val REASSERT_SESSION_INTERVAL_MS = 15_000L
    }

    private var tapCount = 0
    private var paused = false
    private var mediaSession: MediaSessionCompat? = null
    private var backgroundEngine: FlutterEngine? = null
    private var backgroundChannel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val reassertSessionRunnable = object : Runnable {
        override fun run() {
            if (mediaSession != null) {
                mediaSession?.isActive = true
            }
            mainHandler.postDelayed(this, REASSERT_SESSION_INTERVAL_MS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                tapCount = intent.getIntExtra(EXTRA_COUNT, 0)
                paused = false
                ensureChannel()
                startForeground(NOTIFICATION_ID, buildNotification())
                startMediaSession()
                if (intent.hasExtra(EXTRA_SESSION_ID)) {
                    val sessionId = intent.getIntExtra(EXTRA_SESSION_ID, -1)
                    val cumulativeBase = intent.getIntExtra(EXTRA_CUMULATIVE_BASE, 0)
                    getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit()
                        .putInt(PREF_ACTIVE_SESSION_ID, sessionId)
                        .putInt(PREF_CUMULATIVE_BASE, cumulativeBase)
                        .apply()
                    startBackgroundEngine(sessionId)
                }
            }
            ACTION_PAUSE -> {
                paused = true
                updateNotification()
                sendBroadcast(Intent(BROADCAST_STATE_CHANGED).putExtra(EXTRA_PAUSED, true))
            }
            ACTION_RESUME -> {
                paused = false
                updateNotification()
                sendBroadcast(Intent(BROADCAST_STATE_CHANGED).putExtra(EXTRA_PAUSED, false))
            }
            ACTION_UPDATE_COUNT -> {
                tapCount = intent.getIntExtra(EXTRA_COUNT, tapCount)
                updateNotification()
            }
            ACTION_UPDATE_SESSION_ID -> {
                val sessionId = intent.getIntExtra(EXTRA_SESSION_ID, -1)
                if (sessionId != -1) {
                    val cumulativeBase = intent.getIntExtra(EXTRA_CUMULATIVE_BASE, 0)
                    getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit()
                        .putInt(PREF_ACTIVE_SESSION_ID, sessionId)
                        .putInt(PREF_CUMULATIVE_BASE, cumulativeBase)
                        .apply()
                    backgroundChannel?.invokeMethod(
                        "updateSessionId",
                        mapOf("sessionId" to sessionId),
                    )
                }
            }
            ACTION_END -> {
                sendBroadcast(Intent(BROADCAST_STATE_CHANGED).putExtra(EXTRA_ENDED, true))
                getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit()
                    .remove(PREF_ACTIVE_SESSION_ID)
                    .remove(PREF_CUMULATIVE_BASE)
                    .apply()
                stopMediaSession()
                stopBackgroundEngine()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_STICKY
    }

    /** Registers the MediaSession and hands volume-key handling to
     * [VolumeProviderCompat.onAdjustVolume] instead of the system — see the
     * class doc for why this is the capture mechanism. */
    private fun startMediaSession() {
        if (mediaSession != null) return

        val volumeProvider = object : VolumeProviderCompat(
            VOLUME_CONTROL_RELATIVE,
            /* maxVolume = */ 100,
            /* currentVolume = */ 50,
        ) {
            override fun onAdjustVolume(direction: Int) {
                // ADJUST_RAISE / ADJUST_LOWER are the two physical keys;
                // ADJUST_SAME (0) isn't a real press and is ignored. Both
                // real directions count as one tap — which key was
                // pressed doesn't matter for a chant count, and forcing
                // the user to remember "up vs down" would be exactly the
                // kind of screen-off friction this feature exists to
                // avoid.
                if (direction == 0) return
                if (paused) return
                tapCount++
                vibrate()
                updateNotification()
                sendBroadcast(
                    Intent(BROADCAST_TAP_CAPTURED).putExtra(EXTRA_TAP_COUNT, tapCount),
                )
                // Best-effort: the count/notification/vibration above have
                // already happened regardless of whether this succeeds.
                backgroundChannel?.invokeMethod("recordTap", null)
            }
        }

        val session = MediaSessionCompat(this, "JapaSession")
        session.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setState(PlaybackStateCompat.STATE_PLAYING, 0, 1.0f)
                .setActions(PlaybackStateCompat.ACTION_PLAY_PAUSE)
                .build(),
        )
        session.setPlaybackToRemote(volumeProvider)
        session.isActive = true
        mediaSession = session
        mainHandler.postDelayed(reassertSessionRunnable, REASSERT_SESSION_INTERVAL_MS)
    }

    private fun stopMediaSession() {
        mainHandler.removeCallbacks(reassertSessionRunnable)
        mediaSession?.isActive = false
        mediaSession?.release()
        mediaSession = null
    }

    /** Spins up the headless Dart isolate a screen-off session persists
     * taps through — see the class doc for why this is separate from the
     * main UI's engine. */
    private fun startBackgroundEngine(sessionId: Int) {
        if (backgroundEngine != null) return

        val loader = FlutterInjector.instance().flutterLoader()
        if (!loader.initialized()) {
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)
        }

        val engine = FlutterEngine(this)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(),
                BACKGROUND_ENTRYPOINT_LIBRARY,
                BACKGROUND_ENTRYPOINT_FUNCTION,
            ),
        )

        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, BACKGROUND_ISOLATE_CHANNEL)
        channel.invokeMethod("init", mapOf("sessionId" to sessionId))

        backgroundEngine = engine
        backgroundChannel = channel
    }

    private fun stopBackgroundEngine() {
        backgroundChannel = null
        backgroundEngine?.destroy()
        backgroundEngine = null
    }

    private fun vibrate() {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(VIBRATOR_SERVICE) as Vibrator
        }
        vibrator.vibrate(
            VibrationEffect.createOneShot(TAP_VIBRATION_MS, VibrationEffect.DEFAULT_AMPLITUDE),
        )
    }

    private fun updateNotification() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification())
    }

    private fun buildNotification(): Notification {
        val pauseResumeAction = if (paused) {
            NotificationCompat.Action(
                android.R.drawable.ic_media_play,
                "Resume",
                actionPendingIntent(ACTION_RESUME),
            )
        } else {
            NotificationCompat.Action(
                android.R.drawable.ic_media_pause,
                "Pause",
                actionPendingIntent(ACTION_PAUSE),
            )
        }
        val endAction = NotificationCompat.Action(
            android.R.drawable.ic_menu_close_clear_cancel,
            "End",
            actionPendingIntent(ACTION_END),
        )
        val contentText = if (paused) "Paused — $tapCount chants" else "$tapCount chants"

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Japa in progress")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(pauseResumeAction)
            .addAction(endAction)
            .setContentIntent(openAppPendingIntent())
            .build()
    }

    private fun actionPendingIntent(action: String): PendingIntent {
        val intent = Intent(this, JapaForegroundService::class.java).setAction(action)
        return PendingIntent.getService(
            this,
            action.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun openAppPendingIntent(): PendingIntent {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        return PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Japa session",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Your live chant count while chanting screen-off"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    override fun onDestroy() {
        stopMediaSession()
        stopBackgroundEngine()
        super.onDestroy()
    }
}
