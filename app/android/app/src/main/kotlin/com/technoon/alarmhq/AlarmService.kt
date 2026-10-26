package com.technoon.alarmhq

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import org.json.JSONObject

/**
 * Foreground service that sounds the alarm: plays the tone (with optional
 * stepped gradual volume — 10%/35%/65%/100% on STREAM_ALARM), vibrates,
 * and brings up the full-screen UI.
 * Also handles tone previews from the editor screen.
 */
class AlarmService : Service() {

    companion object {
        const val ACTION_START = "com.technoon.alarmhq.START"
        const val ACTION_PREVIEW = "com.technoon.alarmhq.PREVIEW"
        const val ACTION_STOP = "com.technoon.alarmhq.STOP"
        // v2.26: stop the ringing sound/vibration ONLY — used after a
        // successful snooze, where scheduleSnooze() has just shown the
        // persistent "Snoozed until X" notification. Unlike ACTION_STOP,
        // this must NOT cancel notifications or stop the service.
        const val ACTION_STOP_RINGING = "com.technoon.alarmhq.STOP_RINGING"
        const val ACTION_SNOOZED = "com.technoon.alarmhq.SNOOZED"
        // v2.21: snooze directly from the ringing notification (lock screen).
        const val ACTION_SNOOZE = "com.technoon.alarmhq.SNOOZE"
        // v2.84: tell FullScreenAlarmActivity to finish. Notification
        // Stop/Snooze stop the sound via the service, but the activity
        // never heard about it and stayed stuck on screen.
        const val ACTION_DISMISS_FULLSCREEN =
            "com.technoon.alarmhq.DISMISS_FULLSCREEN"
        // v2.14: new channel ID — the old channel was created with
        // IMPORTANCE_HIGH and Android never upgrades an existing channel's
        // importance. Fresh ID forces MAX, required for full-screen intent.
        private const val CHANNEL_ID = "alarmhq_alarm_v2"
        private const val NOTIF_ID = 1001
        private const val SNOOZED_NOTIF_ID = 1002

        // Currently-ringing alarm, visible to MainActivity/Flutter so the
        // in-app ringing dialog can show Dismiss/Snooze while ringing.
        // Same process, so plain statics are fine.
        @Volatile var ringingAlarmJson: String? = null
            private set
        @Volatile var ringingSnoozeCount: Int = 0
            private set
    }

    private var player: MediaPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var vibrator: Vibrator? = null
    private val handler = Handler(Looper.getMainLooper())
    // v2.29: STREAM_ALARM fade state. MediaPlayer.setVolume() is silently
    // ignored on some OEM ROMs (ColorOS/Realme), so the fade is done on the
    // system alarm-stream volume instead.
    private var savedAlarmVolume: Int = -1 // -1 = no fade active / nothing to restore
    private var streamRampRunnable: Runnable? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK, "AlarmHQ::fire"
        ).apply {
            acquire(5 * 60 * 1000L) // fail-safe release after 5 min
        }
        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager)
                .defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_PREVIEW -> {
                val uri = intent.getStringExtra("toneUri") ?: return START_NOT_STICKY
                val volume = intent.getFloatExtra("volume", 0.8f)
                startForegroundService(getString(R.string.alarm_service_notif), null)
                playTone(uri, fadeInSeconds = 0, fixedVolume = volume)
            }
            ACTION_STOP -> {
                // If this Stop came from the snoozed notification, also
                // cancel the pending snooze alarm.
                val snoozeId = intent.getIntExtra("snoozeAlarmId", -1)
                if (snoozeId >= 0) {
                    AlarmScheduler.cancelSnoozeOnly(this, snoozeId)
                }
                stopEverything()
            }
            ACTION_STOP_RINGING -> {
                // v2.26: stop the ringing sound/vibration only. Sent by
                // FullScreenAlarmActivity.doSnooze() (and the other snooze
                // paths) AFTER scheduleSnooze() has shown the persistent
                // "Snoozed until X" notification — that notification must
                // survive, so no cancelSnoozedNotification(), no
                // stopForeground(), no stopSelf() here.
                stopRingingOnly()
            }
            ACTION_SNOOZED -> {
                // Persistent "Snoozed until X" notification (Xiaomi-style).
                val trigger = intent.getLongExtra("snoozeTrigger", 0L)
                val alarmId = intent.getIntExtra("snoozeAlarmId", -1)
                if (trigger > 0L) {
                    // v2.26: the ringing sound may still be playing — stop
                    // it before showing the persistent snoozed notification.
                    stopPlayback()
                    ringingAlarmJson = null
                    ringingSnoozeCount = 0
                    showSnoozedNotification(trigger, alarmId)
                }
            }
            ACTION_SNOOZE -> {
                // v2.21: snooze tapped in the ringing notification (works
                // from the lock screen). Mirrors the full-screen UI's
                // doSnooze() logic.
                val alarmJson = intent.getStringExtra("alarmJson")
                    ?: ringingAlarmJson
                val snoozeCount = if (intent.hasExtra("snoozeCount"))
                    intent.getIntExtra("snoozeCount", 0)
                else ringingSnoozeCount
                if (alarmJson != null) {
                    val alarm = try { JSONObject(alarmJson) }
                    catch (_: Exception) { JSONObject() }
                    val id = alarm.optInt("id", -1)
                    val minutes = alarm.optInt("snoozeMinutes", 10)
                    val storedDef = if (id >= 0)
                        AlarmScheduler.getDef(this, id) else null
                    val max = storedDef?.optInt("maxSnoozes", -2)
                        ?.takeIf { it != -2 }
                        ?: alarm.optInt("maxSnoozes", 3)
                    val canSnooze = max != 0 &&
                        (max < 0 || snoozeCount < max)
                    if (id >= 0 && canSnooze) {
                        AlarmScheduler.scheduleSnooze(
                            this, id, alarmJson, minutes, snoozeCount + 1
                        )
                        android.util.Log.i(
                            "AlarmHQ",
                            "ACTION_SNOOZE: id=$id for ${minutes}min",
                        )
                        // v2.26: scheduleSnooze() just showed the persistent
                        // "Snoozed until X" notification — stop only the
                        // ringing, never stopEverything() (which would
                        // cancel the notification we just created).
                        stopRingingOnly()
                    } else {
                        android.util.Log.w(
                            "AlarmHQ",
                            "ACTION_SNOOZE rejected: id=$id canSnooze=$canSnooze",
                        )
                        stopEverything()
                    }
                } else {
                    // No alarm JSON — nothing to snooze; just stop ringing.
                    stopEverything()
                }
            }
            else -> { // ACTION_START (or null action = start)
                val alarmJson = intent?.getStringExtra("alarmJson") ?: return START_NOT_STICKY
                val snoozeCount = intent.getIntExtra("snoozeCount", 0)
                val alarm = try { JSONObject(alarmJson) } catch (_: Exception) {
                    return START_NOT_STICKY
                }
                val label = alarm.optString("label", "").ifEmpty {
                    getString(R.string.alarm)
                }
                ringingAlarmJson = alarmJson
                ringingSnoozeCount = snoozeCount
                // A firing snooze replaces the "Snoozed until X" notice.
                cancelSnoozedNotification()
                startForegroundService(label, Pair(alarmJson, snoozeCount))
                // v2.47: start vibration AFTER playTone — playTone() begins
                // with stopPlayback(), which cancels the vibrator. Starting
                // it first meant the vibration was killed instantly and the
                // phone never vibrated.
                ensureAlarmVolume()
                playTone(
                    alarm.optString("toneUri", "asset://assets/tones/alarmhq-classic.wav"),
                    fadeInSeconds = alarm.optInt("fadeInSeconds", 30),
                    fixedVolume = null,
                )
                if (alarm.optBoolean("vibration", true)) startVibration()
                launchFullScreen(alarmJson, snoozeCount)
            }
        }
        return START_NOT_STICKY
    }

    /**
     * @param fullScreen null for previews; Pair(alarmJson, snoozeCount) for a
     * real alarm — the notification then carries a full-screen intent, which
     * is the documented way to pop an alarm UI over the lock screen
     * (USE_FULL_SCREEN_INTENT is declared in the manifest).
     *
     * Real alarms use a Xiaomi-style custom layout: big time, info line,
     * and a round blue Stop button (RemoteViews).
     */
    private fun startForegroundService(title: String, fullScreen: Pair<String, Int>?) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // v2.14: remove the stale HIGH-importance channel so only the
            // fresh MAX channel remains.
            try { nm.deleteNotificationChannel("alarmhq_alarm") } catch (_: Exception) {}
            val channel = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.alarm_channel_name),
                NotificationManager.IMPORTANCE_MAX,
            ).apply { description = getString(R.string.alarm_channel_desc) }
            nm.createNotificationChannel(channel)
        }

        // Stop action: tapping the round blue button stops the alarm.
        val stopIntent = Intent(this, AlarmService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPending = android.app.PendingIntent.getService(
            this, 3001, stopIntent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                android.app.PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_ALARM)
            .setPriority(Notification.PRIORITY_MAX)
            // v2.21: explicit public visibility so the alarm always shows
            // its content on the lock screen.
            .setVisibility(Notification.VISIBILITY_PUBLIC)

        if (fullScreen != null) {
            val (alarmJson, snoozeCount) = fullScreen
            val alarm = try { JSONObject(alarmJson) } catch (_: Exception) { JSONObject() }
            val alarmId = alarm.optInt("id", -1)
            val label = alarm.optString("label", "").ifEmpty {
                getString(R.string.alarm)
            }
            // Big 12-hour time, e.g. "09:40".
            val cal = java.util.Calendar.getInstance()
            var h12 = cal.get(java.util.Calendar.HOUR)
            if (h12 == 0) h12 = 12
            val mm = cal.get(java.util.Calendar.MINUTE).toString().padStart(2, '0')
            val timeText = "$h12:$mm"

            // v2.21: snooze button in the notification (lock screen).
            val snoozeIntent = Intent(this, AlarmService::class.java).apply {
                action = ACTION_SNOOZE
                putExtra("alarmJson", alarmJson)
                putExtra("snoozeCount", snoozeCount)
            }
            val snoozePending = android.app.PendingIntent.getService(
                this, 3004, snoozeIntent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                    android.app.PendingIntent.FLAG_IMMUTABLE,
            )
            // maxSnoozes: 0 = no snooze, -1 = unlimited.
            val storedDef = if (alarmId >= 0)
                AlarmScheduler.getDef(this, alarmId) else null
            val maxSnoozes = storedDef?.optInt("maxSnoozes", -2)
                ?.takeIf { it != -2 }
                ?: alarm.optInt("maxSnoozes", 3)
            val canSnooze = maxSnoozes != 0 &&
                (maxSnoozes < 0 || snoozeCount < maxSnoozes)

            // Xiaomi-style custom layout via RemoteViews.
            val views = android.widget.RemoteViews(packageName,
                R.layout.notif_alarm_ringing)
            views.setTextViewText(R.id.notif_time, timeText)
            views.setTextViewText(R.id.notif_info, label)
            views.setTextViewText(R.id.notif_snooze, getString(R.string.snooze))
            views.setOnClickPendingIntent(R.id.notif_snooze, snoozePending)
            if (!canSnooze) {
                views.setViewVisibility(
                    R.id.notif_snooze, android.view.View.GONE)
            }
            views.setTextViewText(R.id.notif_stop, getString(R.string.notif_stop))
            views.setOnClickPendingIntent(R.id.notif_stop, stopPending)
            builder.setCustomContentView(views)
            // Expanded style for the big layout on all API levels.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN) {
                builder.setCustomBigContentView(views)
            }

            val fsIntent = Intent(this, FullScreenAlarmActivity::class.java).apply {
                putExtra("alarmJson", alarmJson)
                putExtra("snoozeCount", snoozeCount)
                // v2.21: alarmId fallback for doSnooze when the JSON
                // lacks an id.
                putExtra("alarmId", alarmId)
            }
            // v2.21: unique request code per alarm so a stale PendingIntent
            // can never carry another alarm's extras.
            val fsPending = android.app.PendingIntent.getActivity(
                this, 2100 + (if (alarmId >= 0) alarmId % 1000 else 0), fsIntent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                    android.app.PendingIntent.FLAG_IMMUTABLE,
            )
            // v2.21: diagnostic — log whether the system will honor the
            // full-screen intent (API 34+ permission check).
            if (Build.VERSION.SDK_INT >= 34) {
                try {
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE)
                        as NotificationManager
                    android.util.Log.i(
                        "AlarmHQ",
                        "fire(id=$alarmId): canUseFullScreenIntent=" +
                            "${nm.canUseFullScreenIntent()}",
                    )
                } catch (_: Exception) { }
            }
            builder.setFullScreenIntent(fsPending, true)
            builder.setContentIntent(fsPending)
        } else {
            builder.setContentTitle(title)
                .setContentText(getString(R.string.alarm_service_notif))
        }
        val notif: Notification = builder.build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIF_ID, notif,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(NOTIF_ID, notif)
        }
    }

    /**
     * Persistent Xiaomi-style "Snoozed until 10:09 PM" notification shown
     * after the user snoozes. Tapping Stop cancels the pending snooze.
     */
    private fun showSnoozedNotification(triggerMillis: Long, alarmId: Int) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.alarm_channel_name),
                NotificationManager.IMPORTANCE_MAX,
            ).apply { description = getString(R.string.alarm_channel_desc) }
            nm.createNotificationChannel(channel)
        }

        // Format trigger as 12-hour time, e.g. "10:09 PM".
        val cal = java.util.Calendar.getInstance().apply {
            timeInMillis = triggerMillis
        }
        var h12 = cal.get(java.util.Calendar.HOUR)
        if (h12 == 0) h12 = 12
        val mm = cal.get(java.util.Calendar.MINUTE).toString().padStart(2, '0')
        val ampm = if (cal.get(java.util.Calendar.AM_PM) ==
            java.util.Calendar.AM) "AM" else "PM"
        val timeText = "$h12:$mm $ampm"

        // Stop action cancels the pending snooze alarm.
        val stopIntent = Intent(this, AlarmService::class.java).apply {
            action = ACTION_STOP
            putExtra("snoozeAlarmId", alarmId)
        }
        val stopPending = android.app.PendingIntent.getService(
            this, 3002, stopIntent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                android.app.PendingIntent.FLAG_IMMUTABLE,
        )

        // Tapping the notification opens the app.
        val openIntent = Intent(this, MainActivity::class.java)
        val openPending = android.app.PendingIntent.getActivity(
            this, 3003, openIntent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                android.app.PendingIntent.FLAG_IMMUTABLE,
        )

        val views = android.widget.RemoteViews(packageName,
            R.layout.notif_alarm_ringing)
        views.setTextViewText(R.id.notif_time, timeText)
        views.setTextViewText(
            R.id.notif_info, getString(R.string.snoozed_until, timeText))
        // v2.21: no snooze-on-snooze — only Stop (cancels the snooze).
        views.setViewVisibility(R.id.notif_snooze, android.view.View.GONE)
        views.setTextViewText(R.id.notif_stop, getString(R.string.notif_stop))
        views.setOnClickPendingIntent(R.id.notif_stop, stopPending)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_ALARM)
            .setPriority(Notification.PRIORITY_HIGH)
            .setCustomContentView(views)
            .setContentIntent(openPending)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN) {
            builder.setCustomBigContentView(views)
        }
        // v2.25: this service was started via startForegroundService()
        // (see AlarmScheduler.scheduleSnooze), so on Android 8+ it MUST
        // call startForeground() within ~5s or the system kills it and the
        // "Snoozed until X" notification never appears. A plain nm.notify()
        // is not enough here.
        val snoozedNotif = builder.build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                SNOOZED_NOTIF_ID, snoozedNotif,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(SNOOZED_NOTIF_ID, snoozedNotif)
        }
    }

    /** Remove the snoozed notification (snooze fired or was cancelled). */
    private fun cancelSnoozedNotification() {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
            nm.cancel(SNOOZED_NOTIF_ID)
        } catch (_: Exception) { }
    }

    private fun resolveUri(toneUri: String): Uri? {
        return when {
            toneUri.startsWith("asset://") -> {
                // Handled separately via AssetFileDescriptor (see playTone).
                null
            }
            toneUri == "system://default" ->
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            toneUri.startsWith("content://") -> Uri.parse(toneUri)
            else -> null
        }
    }

    private fun playTone(toneUri: String, fadeInSeconds: Int, fixedVolume: Float?) {
        stopPlayback()
        // v2.27: diagnostic — the user reported fade-in never ramps.
        // v2.29: also logs the STREAM_ALARM ramp path.
        android.util.Log.i(
            "AlarmHQ",
            "playTone: fadeInSeconds=$fadeInSeconds fixedVolume=$fixedVolume uri=$toneUri",
        )
        // v2.29: fade on the system STREAM_ALARM volume — OEMs (Realme/
        // ColorOS) may ignore MediaPlayer.setVolume(), but the stream
        // volume always works. Not used for previews (fixedVolume != null).
        val useStreamRamp = fadeInSeconds > 0 && fixedVolume == null
        try {
            val mp = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                if (toneUri.startsWith("asset://")) {
                    val rel = toneUri.removePrefix("asset://")
                    // v2.47: pubspec assets are bundled under
                    // flutter_assets/assets/… — the legacy URI form omits the
                    // middle 'assets/'. Try the direct mapping first, then
                    // the legacy form, so old saved alarms keep working.
                    // (Before this fix the lookup always failed and every
                    // "Classic" tone silently fell back to the system sound,
                    // which is why Classic and System sounded identical.)
                    val afd = try {
                        applicationContext.assets.openFd("flutter_assets/$rel")
                    } catch (_: Exception) {
                        applicationContext.assets.openFd("flutter_assets/assets/$rel")
                    }
                    setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                    afd.close()
                } else {
                    val uri = resolveUri(toneUri)
                    if (uri == null) {
                        android.util.Log.w(
                            "AlarmHQ",
                            "playTone: could not resolve $toneUri, aborting",
                        )
                        return
                    }
                    setDataSource(applicationContext, uri)
                }
                isLooping = true
                prepare()
            }
            // v2.29: lower the stream right before the first audible frame
            // so no full-volume blip escapes.
            var rampTarget = -1
            if (useStreamRamp) {
                rampTarget = saveAndLowerAlarmVolume()
            }
            mp.start()
            player = mp
            // Player at full — the audible fade comes from STREAM_ALARM.
            try { mp.setVolume(1.0f, 1.0f) } catch (_: Exception) { }
            if (useStreamRamp) {
                if (rampTarget > 1) {
                    startStreamVolumeRamp(rampTarget, fadeInSeconds)
                } else {
                    // Nothing to ramp (target already at/below minimum).
                    savedAlarmVolume = -1
                }
            }
        } catch (_: Exception) {
            // Tone failed (e.g. revoked file permission) — fall back to the
            // system default alarm sound so the alarm still makes noise.
            tryFallbackTone(fadeInSeconds)
        }
    }

    /**
     * v2.29: remember the user's STREAM_ALARM volume (once per fade) and drop
     * the stream to 1 (minimum audible). Returns the target volume to ramp
     * back up to, or -1 when the stream volume could not be read.
     */
    private fun saveAndLowerAlarmVolume(): Int {
        return try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val max = am.getStreamMaxVolume(AudioManager.STREAM_ALARM)
            if (savedAlarmVolume < 0) {
                savedAlarmVolume = am.getStreamVolume(AudioManager.STREAM_ALARM)
            }
            am.setStreamVolume(AudioManager.STREAM_ALARM, 1, 0)
            android.util.Log.i(
                "AlarmHQ",
                "fadeIn: saved STREAM_ALARM=$savedAlarmVolume/$max, lowered to 1",
            )
            savedAlarmVolume
        } catch (e: Exception) {
            android.util.Log.w(
                "AlarmHQ",
                "fadeIn: could not adjust STREAM_ALARM: ${e.message}",
            )
            -1
        }
    }

    /**
     * v2.29: ramp STREAM_ALARM from 1 up to [target] over [fadeInSeconds],
     * logging every step so a logcat shows exactly what happened.
     */
    private fun startStreamVolumeRamp(target: Int, fadeInSeconds: Int) {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val max = try {
            am.getStreamMaxVolume(AudioManager.STREAM_ALARM)
        } catch (_: Exception) { target }
        // v2.29: the stepped fade the user asked for — 4 distinct steps:
        // 10% -> 35% -> 65% -> 100% of the saved volume, each step lasting
        // fadeInSeconds/4 (e.g. 7.5s per step for a 30s fade).
        val fractions = floatArrayOf(0.10f, 0.35f, 0.65f, 1.0f)
        val stepDelay = (fadeInSeconds * 1000L) / 4
        android.util.Log.i(
            "AlarmHQ",
            "fadeIn: stepped ramp STREAM_ALARM 1 -> $target/$max over " +
                "${fadeInSeconds}s (10%/35%/65%/100%, ${stepDelay}ms per step)",
        )
        var step = 0
        streamRampRunnable = object : Runnable {
            override fun run() {
                // Bail if the fade was cancelled (alarm stopped/dismissed).
                if (savedAlarmVolume < 0) return
                val f = fractions[step]
                val v = Math.round(1 + (target - 1) * f)
                try {
                    am.setStreamVolume(AudioManager.STREAM_ALARM, v, 0)
                    android.util.Log.i(
                        "AlarmHQ",
                        "fadeIn: step ${step + 1}/4 STREAM_ALARM=$v/$target " +
                            "(${(f * 100).toInt()}%)",
                    )
                } catch (_: Exception) { return }
                step++
                if (step < 4) {
                    handler.postDelayed(this, stepDelay)
                } else {
                    // Ramp complete — volume is back at the saved level.
                    savedAlarmVolume = -1
                }
            }
        }
        // Step 1 (10%) applies immediately — the first "very low" seconds.
        handler.post(streamRampRunnable!!)
    }

    /** v2.29: cancel any in-flight ramp and restore the saved stream volume. */
    private fun restoreAlarmVolume() {
        streamRampRunnable?.let { handler.removeCallbacks(it) }
        streamRampRunnable = null
        if (savedAlarmVolume >= 0) {
            try {
                val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                am.setStreamVolume(
                    AudioManager.STREAM_ALARM, savedAlarmVolume, 0
                )
                android.util.Log.i(
                    "AlarmHQ",
                    "fadeIn: restored STREAM_ALARM=$savedAlarmVolume",
                )
            } catch (_: Exception) { }
            savedAlarmVolume = -1
        }
    }

    private fun tryFallbackTone(fadeInSeconds: Int = 0) {
        try {
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: return
            val useStreamRamp = fadeInSeconds > 0
            val mp = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setDataSource(applicationContext, uri)
                isLooping = true
                prepare()
            }
            // v2.29: lower the stream right before the first audible frame.
            var rampTarget = -1
            if (useStreamRamp) {
                rampTarget = saveAndLowerAlarmVolume()
            }
            mp.start()
            player = mp
            try { mp.setVolume(1.0f, 1.0f) } catch (_: Exception) { }
            if (useStreamRamp) {
                if (rampTarget > 1) {
                    startStreamVolumeRamp(rampTarget, fadeInSeconds)
                } else {
                    savedAlarmVolume = -1
                }
            }
        } catch (_: Exception) {
            // v2.29: failed before/while lowering — don't leave the stream
            // stuck at 1. Last resort: vibration only.
            restoreAlarmVolume()
        }
    }

    private fun startVibration() {
        val v = vibrator ?: return
        val pattern = longArrayOf(0, 900, 500, 900, 500)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                v.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                v.vibrate(pattern, 0)
            }
        } catch (_: Exception) { /* vibration unavailable */ }
    }

    private fun launchFullScreen(alarmJson: String, snoozeCount: Int) {
        // Secondary path: the notification's full-screen intent (set above)
        // is the primary, documented route. This direct start is a best
        // effort for unlocked devices; it may be blocked on Android 10+.
        try {
            val i = Intent(this, FullScreenAlarmActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra("alarmJson", alarmJson)
                putExtra("snoozeCount", snoozeCount)
            }
            startActivity(i)
        } catch (_: Exception) { /* notification full-screen intent covers it */ }
    }

    private fun stopPlayback() {
        // v2.29: stop the STREAM_ALARM ramp and give the user their
        // original volume back.
        restoreAlarmVolume()
        try { player?.stop() } catch (_: Exception) {}
        try { player?.release() } catch (_: Exception) {}
        player = null
        try { vibrator?.cancel() } catch (_: Exception) {}
    }

    /** v2.84: notify FullScreenAlarmActivity to finish itself. */
    private fun dismissFullScreen() {
        try {
            sendBroadcast(Intent(ACTION_DISMISS_FULLSCREEN))
        } catch (_: Exception) { }
    }

    private fun stopEverything() {
        ringingAlarmJson = null
        ringingSnoozeCount = 0
        dismissFullScreen()
        stopPlayback()
        cancelSnoozedNotification()
        try { stopForeground(STOP_FOREGROUND_REMOVE) } catch (_: Exception) {}
        stopSelf()
    }

    /**
     * v2.26: stop the sound/vibration and clear the ringing state, but keep
     * the service alive and leave notifications untouched. Used on every
     * successful snooze path, right after scheduleSnooze() has shown the
     * persistent "Snoozed until X" notification.
     */
    private fun stopRingingOnly() {
        ringingAlarmJson = null
        ringingSnoozeCount = 0
        // v2.84: same stuck-screen bug as Stop — a notification Snooze
        // also leaves the full-screen UI up unless told to finish.
        dismissFullScreen()
        stopPlayback()
    }

    override fun onDestroy() {
        stopPlayback()
        try { wakeLock?.release() } catch (_: Exception) {}
        super.onDestroy()
    }

    /** Raise the STREAM_ALARM volume a touch so a muted media volume can't
     *  silence the alarm. Never lowers the user's setting. */
    private fun ensureAlarmVolume() {
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val max = am.getStreamMaxVolume(AudioManager.STREAM_ALARM)
            if (am.getStreamVolume(AudioManager.STREAM_ALARM) < max / 3) {
                am.setStreamVolume(AudioManager.STREAM_ALARM, max / 2, 0)
            }
        } catch (_: Exception) { }
    }
}
