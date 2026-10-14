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
 * gradual volume ramp), vibrates, and brings up the full-screen UI.
 * Also handles tone previews from the editor screen.
 */
class AlarmService : Service() {

    companion object {
        const val ACTION_START = "com.technoon.alarmhq.START"
        const val ACTION_PREVIEW = "com.technoon.alarmhq.PREVIEW"
        const val ACTION_STOP = "com.technoon.alarmhq.STOP"
        const val ACTION_SNOOZED = "com.technoon.alarmhq.SNOOZED"
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
    private var rampRunnable: Runnable? = null

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
            ACTION_SNOOZED -> {
                // Persistent "Snoozed until X" notification (Xiaomi-style).
                val trigger = intent.getLongExtra("snoozeTrigger", 0L)
                val alarmId = intent.getIntExtra("snoozeAlarmId", -1)
                if (trigger > 0L) showSnoozedNotification(trigger, alarmId)
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
                if (alarm.optBoolean("vibration", true)) startVibration()
                ensureAlarmVolume()
                playTone(
                    alarm.optString("toneUri", "asset://tones/alarmhq-classic.wav"),
                    fadeInSeconds = alarm.optInt("fadeInSeconds", 30),
                    fixedVolume = null,
                )
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

        if (fullScreen != null) {
            val (alarmJson, snoozeCount) = fullScreen
            val alarm = try { JSONObject(alarmJson) } catch (_: Exception) { JSONObject() }
            val label = alarm.optString("label", "").ifEmpty {
                getString(R.string.alarm)
            }
            // Big 12-hour time, e.g. "09:40".
            val cal = java.util.Calendar.getInstance()
            var h12 = cal.get(java.util.Calendar.HOUR)
            if (h12 == 0) h12 = 12
            val mm = cal.get(java.util.Calendar.MINUTE).toString().padStart(2, '0')
            val timeText = "$h12:$mm"

            // Xiaomi-style custom layout via RemoteViews.
            val views = android.widget.RemoteViews(packageName,
                R.layout.notif_alarm_ringing)
            views.setTextViewText(R.id.notif_time, timeText)
            views.setTextViewText(R.id.notif_info, label)
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
            }
            val fsPending = android.app.PendingIntent.getActivity(
                this, 2001, fsIntent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                    android.app.PendingIntent.FLAG_IMMUTABLE,
            )
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
        nm.notify(SNOOZED_NOTIF_ID, builder.build())
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
        try {
            val mp = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                if (toneUri.startsWith("asset://")) {
                    val path = "flutter_assets/" +
                        toneUri.removePrefix("asset://")
                    val afd = applicationContext.assets.openFd(path)
                    setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                    afd.close()
                } else {
                    val uri = resolveUri(toneUri) ?: return
                    setDataSource(applicationContext, uri)
                }
                isLooping = true
                prepare()
            }
            val startVol = if (fadeInSeconds > 0 && fixedVolume == null) 0.05f
            else (fixedVolume ?: 1.0f)
            mp.setVolume(startVol, startVol)
            mp.start()
            player = mp
            if (fadeInSeconds > 0 && fixedVolume == null) {
                val steps = 20
                val delay = (fadeInSeconds * 1000L) / steps
                var step = 1
                rampRunnable = object : Runnable {
                    override fun run() {
                        val v = 0.05f + 0.95f * step / steps
                        try { mp.setVolume(v, v) } catch (_: Exception) { return }
                        if (++step <= steps) handler.postDelayed(this, delay)
                    }
                }
                handler.postDelayed(rampRunnable!!, delay)
            }
        } catch (_: Exception) {
            // Tone failed (e.g. revoked file permission) — fall back to the
            // system default alarm sound so the alarm still makes noise.
            tryFallbackTone()
        }
    }

    private fun tryFallbackTone() {
        try {
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: return
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
                setVolume(1.0f, 1.0f)
                start()
            }
            player = mp
        } catch (_: Exception) { /* last resort: vibration only */ }
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
        rampRunnable?.let { handler.removeCallbacks(it) }
        rampRunnable = null
        try { player?.stop() } catch (_: Exception) {}
        try { player?.release() } catch (_: Exception) {}
        player = null
        try { vibrator?.cancel() } catch (_: Exception) {}
    }

    private fun stopEverything() {
        ringingAlarmJson = null
        ringingSnoozeCount = 0
        stopPlayback()
        cancelSnoozedNotification()
        try { stopForeground(STOP_FOREGROUND_REMOVE) } catch (_: Exception) {}
        stopSelf()
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
