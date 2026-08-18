package com.anhad.anhad

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
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

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startSession" -> {
                    val count = call.argument<Int>("count") ?: 0
                    // Only the initial start goes through startForegroundService —
                    // it's the one call Android requires a startForeground()
                    // response to within 5s. Everything else below just talks to
                    // the already-running foreground service via plain
                    // startService, which carries no such obligation and would
                    // risk an ANR if made to repeat it on every action.
                    startForegroundServiceAction(JapaForegroundService.ACTION_START, count)
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
                    startServiceAction(JapaForegroundService.ACTION_UPDATE_COUNT, count)
                    result.success(null)
                }
                "isIgnoringBatteryOptimizations" -> {
                    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(packageName))
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

    private fun startForegroundServiceAction(action: String, count: Int? = null) {
        val intent = Intent(this, JapaForegroundService::class.java).setAction(action)
        if (count != null) intent.putExtra(JapaForegroundService.EXTRA_COUNT, count)
        ContextCompat.startForegroundService(this, intent)
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
