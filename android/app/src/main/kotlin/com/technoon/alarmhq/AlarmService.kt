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
        private const val CHANNEL_ID = "alarmhq_alarm"
        private const val NOTIF_ID = 1001
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
            ACTION_STOP -> stopEverything()
            else -> { // ACTION_START (or null action = start)
                val alarmJson = intent?.getStringExtra("alarmJson") ?: return START_NOT_STICKY
                val snoozeCount = intent.getIntExtra("snoozeCount", 0)
                val alarm = try { JSONObject(alarmJson) } catch (_: Exception) {
                    return START_NOT_STICKY
                }
                val label = alarm.optString("label", "").ifEmpty {
                    getString(R.string.alarm)
                }
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
     */
    private fun startForegroundService(title: String, fullScreen: Pair<String, Int>?) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.alarm_channel_name),
                NotificationManager.IMPORTANCE_HIGH,
            ).apply { description = getString(R.string.alarm_channel_desc) }
            nm.createNotificationChannel(channel)
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
            .setContentTitle(title)
            .setContentText(getString(R.string.alarm_service_notif))
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_ALARM)
            .setPriority(Notification.PRIORITY_MAX)
        if (fullScreen != null) {
            val fsIntent = Intent(this, FullScreenAlarmActivity::class.java).apply {
                putExtra("alarmJson", fullScreen.first)
                putExtra("snoozeCount", fullScreen.second)
            }
            val fsPending = android.app.PendingIntent.getActivity(
                this, 2001, fsIntent,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                    android.app.PendingIntent.FLAG_IMMUTABLE,
            )
            builder.setFullScreenIntent(fsPending, true)
            builder.setContentIntent(fsPending)
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
        stopPlayback()
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
