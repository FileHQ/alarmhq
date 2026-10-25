package com.technoon.alarmhq

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
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
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : Activity() {

    private var flutterEngine: FlutterEngine? = null
    private var alarmChannel: MethodChannel? = null
    private var pendingPickResult: MethodChannel.Result? = null
    private var pendingNotifResult: MethodChannel.Result? = null
    // v2.70: Current tab reported by Flutter (0=Alarms). Native back
    // handling needs it because this is a plain Activity, not
    // FlutterActivity — Flutter's own back handling never fires here.
    private var currentTab = 0

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

    // v2.73: FORWARD back presses to the Flutter engine. Root cause
    // of all back-button failures: this plain Activity never forwarded
    // back to Flutter's Navigator, so the Activity just finished (app
    // exit) before Dart could pop a route, switch to tab 0, or show
    // the exit dialog. NavigationChannel.popRoute() sends the standard
    // pop message; Dart's Navigator + WillPopScope then do the right
    // thing. ONLY onBackPressed (covers button + gesture); dispatchKey
    // Event caused double popRoute sends (the 3-press bug).
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        // Never call super: that finishes the Activity (app-exit bug).
        flutterEngine?.navigationChannel?.popRoute()
    }

    private fun setupChannels(engine: FlutterEngine) {
        val channel = MethodChannel(
            engine.dartExecutor.binaryMessenger,
            "com.technoon.alarmhq/alarm",
        )
        alarmChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                // v2.70: Flutter reports tab changes so native back
                // handling knows whether to go to tab 0 or exit.
                "setCurrentTab" -> {
                    currentTab = (call.argument<Number>("tab")?.toInt()) ?: 0
                    result.success(null)
                }
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
                // v2.27: cancel only the regular occurrence — keeps a
                // pending snooze one-shot alive. Used by reschedule().
                "cancelRegularAlarm" -> {
                    val id = call.argument<Number>("id")?.toInt() ?: -1
                    if (id >= 0) AlarmScheduler.cancelRegular(this, id)
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
                // ---- date & time settings (v2.56): for the atomic
                // "Fix phone time" flow — opens system Date & Time so the
                // user can match it to the floating atomic clock.
                "openDateTimeSettings" -> {
                    startActivity(Intent(Settings.ACTION_DATE_SETTINGS))
                    result.success(null)
                }
                // v2.66: Atomic time notification (replaces overlay on Realme).
                // Shows an ongoing notification with the atomic time so the
                // user can see it while in Date & Time settings.
                "showAtomicTimeNotification" -> {
                    val timeText = call.argument<String>("timeText") ?: ""
                    val dateText = call.argument<String>("dateText") ?: ""
                    try {
                        val nm = getSystemService(
                            Context.NOTIFICATION_SERVICE
                        ) as NotificationManager
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val channel = NotificationChannel(
                                "atomic_time",
                                "Atomic Clock",
                                NotificationManager.IMPORTANCE_DEFAULT,
                            )
                            nm.createNotificationChannel(channel)
                        }
                        val notif = NotificationCompat.Builder(this, "atomic_time")
                            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                            .setContentTitle("⏱️ Atomic Time: $timeText")
                            .setContentText(dateText)
                            .setOngoing(true)
                            .setAutoCancel(false)
                            .build()
                        nm.notify(9999, notif)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "hideAtomicTimeNotification" -> {
                    try {
                        val nm = getSystemService(
                            Context.NOTIFICATION_SERVICE
                        ) as NotificationManager
                        nm.cancel(9999)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                // ---- native atomic overlay (v2.69, ClockSync-style) ----
                // Direct WindowManager overlay via a native Service — works
                // on non-rooted devices (only needs SYSTEM_ALERT_WINDOW).
                "showNativeAtomicOverlay" -> {
                    try {
                        val offsetMs = (call.argument<Number>("offsetMs")?.toLong()) ?: 0L
                        val intent = Intent(this, AtomicOverlayNativeService::class.java).apply {
                            putExtra(AtomicOverlayNativeService.EXTRA_OFFSET_MS, offsetMs)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "hideNativeAtomicOverlay" -> {
                    try {
                        stopService(Intent(this, AtomicOverlayNativeService::class.java))
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                // ---- root check + ClockSync time-set (v2.69) ----
                "isRooted" -> {
                    result.success(checkRoot())
                }
                "setSystemTimeRoot" -> {
                    val timeMs = (call.argument<Number>("timeMs")?.toLong()) ?: 0L
                    result.success(setSystemTimeViaRoot(timeMs))
                }
                // v2.73: Exit app — SystemNavigator.pop() does NOT work
                // in a plain Activity (engine has no Activity binding),
                // so the dialog's Yes button must finish natively.
                "exitApp" -> {
                    finishAffinity()
                    result.success(null)
                }
                // v2.72: Overlay permission check (SYSTEM_ALERT_WINDOW).
                "canDrawOverlays" -> {
                    val ok = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        Settings.canDrawOverlays(this)
                    } else {
                        true
                    }
                    result.success(ok)
                }
                // ---- timezone (v2.69, works WITHOUT root) ----
                "setTimeZone" -> {
                    val zoneId = call.argument<String>("zoneId") ?: ""
                    try {
                        val am = getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
                        am.setTimeZone(zoneId)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                // ---- full-screen intent (v2.11, CRITICAL): on Android 14+
                // USE_FULL_SCREEN_INTENT must be granted by the user, or
                // setFullScreenIntent() is silently ignored and the alarm
                // never appears on the lock screen.
                "canUseFullScreenIntent" -> {
                    val granted =
                        if (Build.VERSION.SDK_INT >= 34) {
                            val nm = getSystemService(
                                Context.NOTIFICATION_SERVICE
                            ) as NotificationManager
                            nm.canUseFullScreenIntent()
                        } else {
                            true // auto-granted below Android 14
                        }
                    result.success(granted)
                }
                "needsFullScreenIntentCard" -> {
                    // Only Android 14+ needs the user to grant this.
                    result.success(Build.VERSION.SDK_INT >= 34)
                }
                "openFullScreenIntentSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= 34) {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                                    Uri.parse("package:$packageName"),
                                )
                            )
                        }
                    } catch (_: Exception) { /* best effort */ }
                    result.success(null)
                }
                // ---- autostart (v2.4): Xiaomi/Oppo/Vivo/Huawei kill
                // background alarms without this; no API to check it, so
                // we just open the manufacturer's autostart page.
                "openAutostartSettings" -> {
                    openAutostartSettings()
                    result.success(null)
                }
                // ---- device info (v2.10) ----
                "getManufacturer" ->
                    result.success(Build.MANUFACTURER ?: "")
                // ---- OEM extras (v2.18): ColorOS (Realme/Oppo/OnePlus)
                // hides critical toggles ("Show on Lock screen",
                // "Open new windows in background") inside the app's
                // system settings page — guide the user there.
                "isColorOsDevice" -> {
                    val m = (Build.MANUFACTURER ?: "").lowercase()
                    result.success(
                        m.contains("realme") ||
                            m.contains("oppo") ||
                            m.contains("oneplus"),
                    )
                }
                "openAppDetailsSettings" -> {
                    try {
                        startActivity(
                            Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.parse("package:$packageName"),
                            ),
                        )
                    } catch (_: Exception) { /* best effort */ }
                    result.success(null)
                }
                // ---- device info (v2.18) ----
                "sdkInt" ->
                    result.success(Build.VERSION.SDK_INT)
                // ---- app version (v2.20): dynamic version display instead
                // of a hardcoded string in Settings.
                "getAppVersion" -> {
                    try {
                        val pi = if (Build.VERSION.SDK_INT >=
                            Build.VERSION_CODES.TIRAMISU
                        ) {
                            packageManager.getPackageInfo(
                                packageName,
                                android.content.pm.PackageManager
                                    .PackageInfoFlags.of(0),
                            )
                        } else {
                            @Suppress("DEPRECATION")
                            packageManager.getPackageInfo(packageName, 0)
                        }
                        result.success(pi.versionName)
                    } catch (_: Exception) {
                        result.success(null)
                    }
                }
                // ---- in-app ringing dialog support ----
                "isAlarmRinging" ->
                    result.success(AlarmService.ringingAlarmJson != null)
                // ---- snooze countdown (v2.4) ----
                "getSnoozeTrigger" -> {
                    val id = call.argument<Number>("id")?.toInt() ?: -1
                    val t = if (id >= 0)
                        AlarmScheduler.getSnoozeTrigger(this, id) else null
                    result.success(t)
                }
                // v2.23: snooze count for the "N left" badge text.
                "getSnoozeCount" -> {
                    val id = call.argument<Number>("id")?.toInt() ?: -1
                    val c = if (id >= 0)
                        AlarmScheduler.getSnoozeCount(this, id) else 0
                    result.success(c)
                }
                // v2.26: fallback — read the snooze trigger directly from
                // the "alarmhq_prefs" backup file when getSnoozeTrigger
                // (native misc) misses.
                "getSnoozeTriggerBackup" -> {
                    val id = call.argument<Number>("id")?.toInt() ?: -1
                    val t = if (id >= 0)
                        AlarmScheduler.getSnoozeTriggerBackup(this, id) else null
                    result.success(t)
                }
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
                            // v2.13: read maxSnoozes from the CURRENT stored
                            // definition (not the potentially stale ringing
                            // JSON) so a setting changed after scheduling
                            // is respected. Falls back to the ringing JSON.
                            val stored = if (id >= 0)
                                AlarmScheduler.getDef(this, id) else null
                            val max = stored?.optInt("maxSnoozes", -2)
                                ?.takeIf { it != -2 }
                                ?: alarm.optInt("maxSnoozes", 3)
                            android.util.Log.i(
                                "AlarmHQ",
                                "snoozeAlarm: id=$id count=$count max=$max",
                            )
                            // max: 0 = no snooze, -1 = unlimited.
                            // "No more left" when used >= max.
                            if (id >= 0 && max != 0 &&
                                (max < 0 || count < max)) {
                                AlarmScheduler.scheduleSnooze(
                                    this, id, json, minutes, count + 1
                                )
                                ok = true
                            } else {
                                android.util.Log.w(
                                    "AlarmHQ",
                                    "snoozeAlarm REJECTED: count=$count max=$max",
                                )
                            }
                        } catch (_: Exception) { /* parse failed */ }
                    }
                    // Stop the current ringing either way — but on a successful
                    // snooze, keep the "Snoozed until X" notification that
                    // scheduleSnooze() just showed (v2.26: ACTION_STOP would
                    // cancel it via stopEverything()).
                    startService(
                        Intent(this, AlarmService::class.java).apply {
                            action = if (ok)
                                AlarmService.ACTION_STOP_RINGING
                            else
                                AlarmService.ACTION_STOP
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

    /**
     * Open the manufacturer's autostart / background-start management page.
     * Xiaomi, Oppo/Realme, Vivo, Huawei and OnePlus all kill background
     * alarms unless the app is whitelisted here. Falls back to the app's
     * system settings page when no known component resolves.
     */
    private fun openAutostartSettings() {
        val candidates = listOf(
            // Xiaomi (MIUI)
            "com.miui.securitycenter" to
                "com.miui.permcenter.autostart.AutoStartManagementActivity",
            // Oppo / Realme (ColorOS)
            "com.coloros.safecenter" to
                "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            "com.coloros.safecenter" to
                "com.coloros.safecenter.permission.startupapp.StartupAppListActivity",
            "com.oppo.safe" to
                "com.oppo.safe.permission.startup.StartupAppListActivity",
            // Realme UI 3.0+ / ColorOS 12+ (Oplus)
            "com.oplus.safecenter" to
                "com.oplus.safecenter.permission.startup.StartupAppListActivity",
            "com.oplus.safecenter" to
                "com.oplus.safecenter.permission.startupapp.StartupAppListActivity",
            // Vivo (Funtouch)
            "com.vivo.permissionmanager" to
                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            "com.iqoo.secure" to
                "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
            // Huawei (EMUI)
            "com.huawei.systemmanager" to
                "com.huawei.systemmanager.optimize.process.ProtectActivity",
            "com.huawei.systemmanager" to
                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            // OnePlus (OxygenOS)
            "com.oneplus.security" to
                "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity",
            // Samsung
            "com.samsung.android.lool" to
                "com.samsung.android.sm.ui.battery.BatteryActivity",
        )
        for ((pkg, cls) in candidates) {
            try {
                val intent = Intent().setClassName(pkg, cls)
                // Only fire when the target actually exists on this device.
                if (intent.resolveActivity(packageManager) != null) {
                    startActivity(intent)
                    return
                }
            } catch (_: Exception) { /* try next */ }
        }
        // Fallback: the app's own system settings page.
        try {
            startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName"),
                )
            )
        } catch (_: Exception) { /* best effort */ }
    }

    // ---- ClockSync-style root helpers (v2.69) ----
    private fun checkRoot(): Boolean {
        // ClockSync tries: su, /system/xbin/su, /system/bin/su
        for (su in arrayOf("su", "/system/xbin/su", "/system/bin/su")) {
            try {
                val p = Runtime.getRuntime().exec(arrayOf(su, "-c", "id"))
                val out = p.inputStream.bufferedReader().readText()
                p.waitFor()
                if (out.contains("uid=0")) return true
            } catch (_: Exception) { /* try next */ }
        }
        return false
    }

    private fun runSuCommand(cmd: String): Boolean {
        for (su in arrayOf("su", "/system/xbin/su", "/system/bin/su")) {
            try {
                val p = Runtime.getRuntime().exec(arrayOf(su, "-c", cmd))
                p.waitFor()
                if (p.exitValue() == 0) return true
            } catch (_: Exception) { /* try next */ }
        }
        return false
    }

    private fun setSystemTimeViaRoot(timeMs: Long): Boolean {
        // ClockSync method: chmod 666 /dev/alarm -> setCurrentTimeMillis
        // -> chmod 664 /dev/alarm. Only works on rooted devices.
        if (!checkRoot()) return false
        runSuCommand("chmod 666 /dev/alarm")
        val ok = try {
            android.os.SystemClock.setCurrentTimeMillis(timeMs)
        } catch (_: Exception) {
            false
        }
        runSuCommand("chmod 664 /dev/alarm")
        return ok
    }
}
