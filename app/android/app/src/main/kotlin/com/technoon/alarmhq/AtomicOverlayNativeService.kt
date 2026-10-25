package com.technoon.alarmhq

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Native atomic-clock overlay (ClockSync-style).
 *
 * Unlike the system_alert_window Flutter plugin (which spawns a separate
 * FlutterEngine and fails on Realme/ColorOS), this service creates the
 * overlay directly via WindowManager.addView() from native code — the
 * exact approach ClockSync uses in its SyncAssistService.
 *
 * Works on NON-rooted devices: only needs SYSTEM_ALERT_WINDOW permission
 * ("Display over other apps"), granted by the user in Settings.
 *
 * The service receives the atomic offset (atomic - device, in ms) from
 * Flutter, then ticks locally every second: display = deviceTime + offset.
 * This keeps ticking even when the app is in background (settings open).
 */
class AtomicOverlayNativeService : Service() {

    companion object {
        const val EXTRA_OFFSET_MS = "offset_ms"
        var isRunning = false
            private set
    }

    private var windowManager: WindowManager? = null
    private var overlayView: LinearLayout? = null
    private var timeText: TextView? = null
    private var dateText: TextView? = null
    private val handler = Handler(Looper.getMainLooper())
    private var offsetMs: Long = 0L

    private val tickTask = object : Runnable {
        override fun run() {
            // v2.75: Self-healing — if ColorOS/the system detached the
            // overlay view, re-add it instead of staying invisible.
            if (overlayView == null ||
                overlayView?.isAttachedToWindow != true
            ) {
                createOverlay()
            }
            updateDisplay()
            handler.postDelayed(this, 1000)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // v2.73: Persist offset — if ColorOS kills the service and the
        // system restarts it (START_STICKY, null intent), recover the
        // last offset instead of showing device time (offset 0).
        val prefs = getSharedPreferences("atomic_overlay", Context.MODE_PRIVATE)
        val fromIntent = intent?.getLongExtra(EXTRA_OFFSET_MS, Long.MIN_VALUE)
        offsetMs = if (fromIntent != null && fromIntent != Long.MIN_VALUE) {
            prefs.edit().putLong("offset_ms", fromIntent).apply()
            fromIntent
        } else {
            prefs.getLong("offset_ms", 0L)
        }
        // v2.70: Foreground service — REQUIRED. startForegroundService()
        // without startForeground() kills the service after ~5s, which
        // is exactly when Settings opens and the overlay vanished.
        startAsForeground()
        if (overlayView == null) {
            createOverlay()
        }
        handler.removeCallbacks(tickTask)
        handler.post(tickTask)
        isRunning = true
        return START_STICKY
    }

    private fun startAsForeground() {
        val channelId = "atomic_overlay"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(channelId) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(
                        channelId,
                        "Atomic clock overlay",
                        NotificationManager.IMPORTANCE_LOW,
                    )
                )
            }
        }
        // v2.74: setOngoing(true) — ColorOS is less likely to kill a
        // service whose notification the user cannot swipe away.
        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
                .setContentTitle("اٹامک ٹائم اوورلے چل رہا ہے")
                .setContentText("ٹائم سیٹ کرنے کے لیے اوورلے دیکھیں")
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setOngoing(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("اٹامک ٹائم اوورلے چل رہا ہے")
                .setContentText("ٹائم سیٹ کرنے کے لیے اوورلے دیکھیں")
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setOngoing(true)
                .build()
        }
        // v2.71: startForeground can still throw on some OEM builds
        // (missing type, denied) — never let it crash the app.
        try {
            startForeground(1001, notification)
        } catch (_: Exception) {
            // Continue as background service; overlay may still show
            // if SYSTEM_ALERT_WINDOW is granted.
        }
    }

    override fun onDestroy() {
        handler.removeCallbacks(tickTask)
        // v2.73: Only clear persisted offset on explicit user close
        // (the X button calls stopSelf -> onDestroy). System kills do
        // not reliably call onDestroy, so restart recovery still works.
        removeOverlay()
        isRunning = false
        super.onDestroy()
    }

    private fun createOverlay() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            return
        }
        // v2.75: Clean any stale/detached view before creating a new one,
        // else addView throws for a duplicate or leaks the old view.
        try {
            overlayView?.let { windowManager?.removeView(it) }
        } catch (_: Exception) {
            // Already detached — safe to ignore.
        }
        overlayView = null
        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        windowManager = wm

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setBackgroundColor(Color.parseColor("#CC1A1A1A"))
            setPadding(32, 20, 32, 20)
        }
        // Green dot indicator
        val dot = TextView(this).apply {
            text = "⏱️"
            textSize = 22f
            setPadding(0, 0, 16, 0)
        }
        layout.addView(dot)

        val col = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        timeText = TextView(this).apply {
            textSize = 24f
            setTextColor(Color.parseColor("#A3E635"))
            letterSpacing = 0.05f
        }
        col.addView(timeText)
        dateText = TextView(this).apply {
            textSize = 12f
            setTextColor(Color.parseColor("#B3FFFFFF"))
        }
        col.addView(dateText)
        layout.addView(col)

        // Close button
        val close = TextView(this).apply {
            text = "✕"
            textSize = 18f
            setTextColor(Color.parseColor("#B3FFFFFF"))
            setPadding(24, 0, 0, 0)
            setOnClickListener { stopSelf() }
        }
        layout.addView(close)

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_SYSTEM_ALERT
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP
        }
        try {
            wm.addView(layout, params)
            overlayView = layout
        } catch (e: Exception) {
            // Permission revoked or window type blocked — fail silently.
        }
    }

    private fun updateDisplay() {
        val t = Date(System.currentTimeMillis() + offsetMs)
        val timeFmt = SimpleDateFormat("hh:mm:ss a", Locale.US)
        val dateFmt = SimpleDateFormat("d MMMM yyyy", Locale.US)
        timeText?.text = timeFmt.format(t)
        dateText?.text = dateFmt.format(t)
    }

    private fun removeOverlay() {
        try {
            overlayView?.let { windowManager?.removeView(it) }
        } catch (e: Exception) {
            // Already removed.
        }
        overlayView = null
    }
}
