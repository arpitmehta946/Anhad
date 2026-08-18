package com.anhad.anhad

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Keeps a japa (chant) session alive with the screen off (docs/PRD.md
 * §7.4). Phase 1 of the build: the service itself, its lock-screen-visible
 * notification, and pause/end controls. Volume-key tap capture and
 * real-time Isar persistence land in later phases — for now the displayed
 * count is whatever [ACTION_UPDATE_COUNT] last told us, not yet backed by
 * real taps.
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
        const val EXTRA_COUNT = "count"

        // Local broadcast so MainActivity (when running) can reflect
        // notification-button taps in the Flutter UI without polling.
        const val BROADCAST_STATE_CHANGED = "com.anhad.anhad.japa.STATE_CHANGED"
        const val EXTRA_PAUSED = "paused"
        const val EXTRA_ENDED = "ended"
    }

    private var tapCount = 0
    private var paused = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                tapCount = intent.getIntExtra(EXTRA_COUNT, 0)
                paused = false
                ensureChannel()
                startForeground(NOTIFICATION_ID, buildNotification())
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
            ACTION_END -> {
                sendBroadcast(Intent(BROADCAST_STATE_CHANGED).putExtra(EXTRA_ENDED, true))
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_STICKY
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
}
