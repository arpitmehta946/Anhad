package com.anhad.anhad

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Bridges the Flutter japa screen to [JapaForegroundService] and the
 * Android battery-optimization exemption flow (docs/PRD.md §7.4). */
class MainActivity : FlutterActivity() {

    private val channelName = "com.anhad.anhad/japa_background"
    private val saptaSwaraChannelName = "com.anhad.anhad/sapta_swara"
    private var methodChannel: MethodChannel? = null
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null
    private val notificationPermissionRequestCode = 9001

    private val stateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val paused = intent.getBooleanExtra(JapaForegroundService.EXTRA_PAUSED, false)
            val ended = intent.getBooleanExtra(JapaForegroundService.EXTRA_ENDED, false)
            methodChannel?.invokeMethod(
                "onStateChanged",
                mapOf("paused" to paused, "ended" to ended),
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        JapaBellPlayer.preload(this)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startSession" -> {
                    val sessionId = call.argument<Int>("sessionId")
                    val count = call.argument<Int>("count") ?: 0
                    val cumulativeBase = call.argument<Int>("cumulativeBase") ?: 0
                    val malaLength = call.argument<Int>("malaLength") ?: 108
                    // Only the initial start goes through startForegroundService —
                    // it's the one call Android requires a startForeground()
                    // response to within 5s. Everything else below just talks to
                    // the already-running foreground service via plain
                    // startService, which carries no such obligation and would
                    // risk an ANR if made to repeat it on every action.
                    val intent = Intent(this, JapaForegroundService::class.java)
                        .setAction(JapaForegroundService.ACTION_START)
                        .putExtra(JapaForegroundService.EXTRA_COUNT, count)
                        .putExtra(JapaForegroundService.EXTRA_CUMULATIVE_BASE, cumulativeBase)
                        .putExtra(JapaForegroundService.EXTRA_MALA_LENGTH, malaLength)
                    if (sessionId != null) {
                        intent.putExtra(JapaForegroundService.EXTRA_SESSION_ID, sessionId)
                    }
                    ContextCompat.startForegroundService(this, intent)
                    result.success(null)
                }
                "getActiveSessionId" -> {
                    val prefs = getSharedPreferences(JapaForegroundService.PREFS_NAME, MODE_PRIVATE)
                    if (prefs.contains(JapaForegroundService.PREF_ACTIVE_SESSION_ID)) {
                        result.success(
                            mapOf(
                                "sessionId" to prefs.getInt(JapaForegroundService.PREF_ACTIVE_SESSION_ID, -1),
                                "cumulativeBase" to prefs.getInt(JapaForegroundService.PREF_CUMULATIVE_BASE, 0),
                            ),
                        )
                    } else {
                        result.success(null)
                    }
                }
                "updateSessionId" -> {
                    val sessionId = call.argument<Int>("sessionId")
                    val cumulativeBase = call.argument<Int>("cumulativeBase") ?: 0
                    if (sessionId != null) {
                        val intent = Intent(this, JapaForegroundService::class.java)
                            .setAction(JapaForegroundService.ACTION_UPDATE_SESSION_ID)
                            .putExtra(JapaForegroundService.EXTRA_SESSION_ID, sessionId)
                            .putExtra(JapaForegroundService.EXTRA_CUMULATIVE_BASE, cumulativeBase)
                        startService(intent)
                    }
                    result.success(null)
                }
                "updateMalaLength" -> {
                    val malaLength = call.argument<Int>("malaLength") ?: 108
                    val intent = Intent(this, JapaForegroundService::class.java)
                        .setAction(JapaForegroundService.ACTION_UPDATE_MALA_LENGTH)
                        .putExtra(JapaForegroundService.EXTRA_MALA_LENGTH, malaLength)
                    startService(intent)
                    result.success(null)
                }
                "pause" -> {
                    startServiceAction(JapaForegroundService.ACTION_PAUSE)
                    result.success(null)
                }
                "resume" -> {
                    startServiceAction(JapaForegroundService.ACTION_RESUME)
                    result.success(null)
                }
                "end" -> {
                    startServiceAction(JapaForegroundService.ACTION_END)
                    result.success(null)
                }
                "updateCount" -> {
                    val count = call.argument<Int>("count") ?: 0
                    val malaLength = call.argument<Int>("malaLength") ?: 108
                    val intent = Intent(this, JapaForegroundService::class.java)
                        .setAction(JapaForegroundService.ACTION_UPDATE_COUNT)
                        .putExtra(JapaForegroundService.EXTRA_COUNT, count)
                        .putExtra(JapaForegroundService.EXTRA_MALA_LENGTH, malaLength)
                    startService(intent)
                    result.success(null)
                }
                "playCompletionSound" -> {
                    val kind = call.argument<String>("kind")
                    val completionKind = if (kind == "round") {
                        JapaBellPlayer.CompletionKind.ROUND
                    } else {
                        JapaBellPlayer.CompletionKind.TARGET
                    }
                    // Only reached when no screen-off session is active —
                    // JapaSessionController skips this call otherwise,
                    // since JapaForegroundService already owns completion
                    // sounds for every tap source once a session is
                    // running (see its ACTION_UPDATE_COUNT handler).
                    JapaBellPlayer.play(this, completionKind)
                    result.success(null)
                }
                "shouldShowHeadphoneHint" -> {
                    result.success(JapaBellPlayer.consumePendingHeadphoneHint(this))
                }
                "isIgnoringBatteryOptimizations" -> {
                    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(packageName))
                }
                "isRingerSilentOrVibrate" -> {
                    val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    result.success(audioManager.ringerMode != AudioManager.RINGER_MODE_NORMAL)
                }
                "isNotificationPermissionGranted" -> {
                    result.success(isNotificationPermissionGranted())
                }
                "requestNotificationPermission" -> {
                    if (isNotificationPermissionGranted()) {
                        result.success(true)
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        pendingNotificationPermissionResult = result
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            notificationPermissionRequestCode,
                        )
                    } else {
                        // Pre-Android 13 notifications don't need a runtime grant.
                        result.success(true)
                    }
                }
                "requestIgnoreBatteryOptimizations" -> {
                    val intent = Intent(
                        Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                        Uri.parse("package:$packageName"),
                    )
                    startActivity(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, saptaSwaraChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "playTone") {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        SaptaSwaraPlayer.play(this, path)
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun isNotificationPermissionGranted(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == notificationPermissionRequestCode) {
            pendingNotificationPermissionResult?.success(isNotificationPermissionGranted())
            pendingNotificationPermissionResult = null
        }
    }

    private fun startServiceAction(action: String, count: Int? = null) {
        val intent = Intent(this, JapaForegroundService::class.java).setAction(action)
        if (count != null) intent.putExtra(JapaForegroundService.EXTRA_COUNT, count)
        startService(intent)
    }

    override fun onStart() {
        super.onStart()
        val filter = IntentFilter(JapaForegroundService.BROADCAST_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(stateReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(stateReceiver, filter)
        }
    }

    override fun onStop() {
        unregisterReceiver(stateReceiver)
        super.onStop()
    }
}
