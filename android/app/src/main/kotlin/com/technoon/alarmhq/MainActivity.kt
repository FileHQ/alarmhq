package com.technoon.alarmhq

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : Activity() {

    private var flutterEngine: FlutterEngine? = null
    private var pendingPickResult: MethodChannel.Result? = null
    private var pendingNotifResult: MethodChannel.Result? = null

    companion object {
        private const val PICK_AUDIO_REQUEST = 1001
        private const val NOTIF_PERMISSION_REQUEST = 9001
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val engine = FlutterEngine(this)
        flutterEngine = engine
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )

        val flutterView = FlutterView(this)
        setContentView(flutterView)
        flutterView.attachToFlutterEngine(engine)

        requestNotificationPermissionIfNeeded()
        setupChannels(engine)
    }

    private fun setupChannels(engine: FlutterEngine) {
        MethodChannel(
            engine.dartExecutor.binaryMessenger,
            "com.technoon.alarmhq/alarm",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "scheduleAlarm" -> {
                    val id = (call.argument<Number>("id")?.toInt()) ?: -1
                    val trigger = call.argument<Number>("triggerAtMillis")?.toLong()
                        ?: 0L
                    val json = call.argument<String>("alarmJson")
                    if (id < 0 || trigger <= 0 || json.isNullOrEmpty()) {
                        result.success(false)
                    } else {
                        val ok = AlarmScheduler.schedule(this, id, trigger, json)
                        result.success(ok)
                    }
                }
                "cancelAlarm" -> {
                    val id = call.argument<Number>("id")?.toInt() ?: -1
                    if (id >= 0) AlarmScheduler.cancel(this, id)
                    result.success(true)
                }
                "cancelAllAlarms" -> {
                    AlarmScheduler.cancelAll(this)
                    result.success(true)
                }
                "hasExactAlarmPermission" ->
                    result.success(AlarmScheduler.canScheduleExact(this))
                "openExactAlarmSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        // Package URI takes the user straight to this app's
                        // toggle instead of the generic list.
                        startActivity(
                            Intent(
                                Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                                Uri.parse("package:$packageName"),
                            )
                        )
                    }
                    result.success(null)
                }
                "isIgnoringBatteryOptimizations" -> {
                    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(packageName))
                }
                "openBatteryOptimizationSettings" -> {
                    startActivity(
                        Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                            data = Uri.parse("package:$packageName")
                        }
                    )
                    result.success(null)
                }
                "pickAudioFile" -> {
                    pendingPickResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "audio/*"
                    }
                    startActivityForResult(intent, PICK_AUDIO_REQUEST)
                }
                "getSystemDefaultAlarmUri" -> {
                    val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    result.success(uri?.toString())
                }
                "playTonePreview" -> {
                    val uri = call.argument<String>("toneUri") ?: ""
                    val volume =
                        call.argument<Number>("volume")?.toFloat() ?: 0.8f
                    val i = Intent(this, AlarmService::class.java).apply {
                        action = AlarmService.ACTION_PREVIEW
                        putExtra("toneUri", uri)
                        putExtra("volume", volume)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(i)
                    } else {
                        startService(i)
                    }
                    result.success(null)
                }
                "stopTonePreview" -> {
                    val i = Intent(this, AlarmService::class.java).apply {
                        action = AlarmService.ACTION_STOP
                    }
                    startService(i)
                    result.success(null)
                }
                "updateWidget" -> {
                    val text = call.argument<String>("text") ?: ""
                    AlarmScheduler.setNextText(this, text)
                    result.success(null)
                }
                "playTick" -> {
                    try {
                        val tone = ToneGenerator(AudioManager.STREAM_MUSIC, 70)
                        tone.startTone(ToneGenerator.TONE_PROP_BEEP, 60)
                        Handler(Looper.getMainLooper()).postDelayed(
                            { try { tone.release() } catch (_: Exception) {} },
                            300,
                        )
                    } catch (_: Exception) { /* best effort */ }
                    result.success(null)
                }
                "hasNotificationPermission" -> {
                    val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                            PackageManager.PERMISSION_GRANTED
                    } else {
                        true
                    }
                    result.success(granted)
                }
                "requestNotificationPermission" -> {
                    // One-tap system dialog (no settings page needed).
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                            PackageManager.PERMISSION_GRANTED
                    ) {
                        pendingNotifResult = result
                        requestPermissions(
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            NOTIF_PERMISSION_REQUEST,
                        )
                    } else {
                        result.success(true)
                    }
                }
                "openNotificationSettings" -> {
                    val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                        putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    }
                    startActivity(intent)
                    result.success(null)
                }
                "canDrawOverlays" -> {
                    val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        Settings.canDrawOverlays(this)
                    } else {
                        true
                    }
                    result.success(granted)
                }
                "openOverlaySettings" -> {
                    startActivity(
                        Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName"),
                        )
                    )
                    result.success(null)
                }
                // ---- in-app ringing dialog support ----
                "isAlarmRinging" ->
                    result.success(AlarmService.ringingAlarmJson != null)
                "getRingingAlarm" -> {
                    val json = AlarmService.ringingAlarmJson
                    if (json == null) {
                        result.success(null)
                    } else {
                        result.success(
                            mapOf(
                                "alarmJson" to json,
                                "snoozeCount" to AlarmService.ringingSnoozeCount,
                            )
                        )
                    }
                }
                "dismissAlarm" -> {
                    startService(
                        Intent(this, AlarmService::class.java).apply {
                            action = AlarmService.ACTION_STOP
                        }
                    )
                    result.success(true)
                }
                "snoozeAlarm" -> {
                    val json = AlarmService.ringingAlarmJson
                    var ok = false
                    if (json != null) {
                        try {
                            val alarm = JSONObject(json)
                            val id = alarm.optInt("id", -1)
                            val count = AlarmService.ringingSnoozeCount
                            val minutes = alarm.optInt("snoozeMinutes", 10)
                            val max = alarm.optInt("maxSnoozes", 3)
                            if (id >= 0 && max > 0 && count < max) {
                                AlarmScheduler.scheduleSnooze(
                                    this, id, json, minutes, count + 1
                                )
                                ok = true
                            }
                        } catch (_: Exception) { /* parse failed */ }
                    }
                    // Stop the current ringing either way.
                    startService(
                        Intent(this, AlarmService::class.java).apply {
                            action = AlarmService.ACTION_STOP
                        }
                    )
                    result.success(ok)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            engine.dartExecutor.binaryMessenger,
            "com.technoon.alarmhq/prefs",
        ).setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences("alarmhq_prefs", Context.MODE_PRIVATE)
            when (call.method) {
                "getString" -> result.success(
                    prefs.getString(call.argument<String>("key"), null)
                )
                "putString" -> {
                    prefs.edit()
                        .putString(
                            call.argument<String>("key"),
                            call.argument<String>("value"),
                        )
                        .apply()
                    result.success(true)
                }
                "remove" -> {
                    prefs.edit().remove(call.argument<String>("key")).apply()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIF_PERMISSION_REQUEST) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingNotifResult?.success(granted)
            pendingNotifResult = null
        }
    }

    @Deprecated("Use Activity Result API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_AUDIO_REQUEST) {
            val pending = pendingPickResult
            pendingPickResult = null
            if (resultCode == RESULT_OK && data?.data != null) {
                val uri = data.data!!
                try {
                    contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION,
                    )
                } catch (_: SecurityException) { /* best effort */ }
                pending?.success(uri.toString())
            } else {
                pending?.success(null)
            }
        }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIF_PERMISSION_REQUEST)
        }
    }

    override fun onResume() {
        super.onResume()
        flutterEngine?.lifecycleChannel?.appIsResumed()
    }

    override fun onPause() {
        super.onPause()
        flutterEngine?.lifecycleChannel?.appIsInactive()
    }

    override fun onDestroy() {
        flutterEngine?.destroy()
        flutterEngine = null
        super.onDestroy()
    }

    @Suppress("unused")
    private fun am(): AlarmManager =
        getSystemService(Context.ALARM_SERVICE) as AlarmManager
}
