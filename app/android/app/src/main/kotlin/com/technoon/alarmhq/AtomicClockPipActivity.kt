package com.technoon.alarmhq

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Rational
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Atomic clock in Picture-in-Picture (v2.77).
 *
 * Why PiP instead of a service overlay: ColorOS kills our service
 * (even foreground, separate process, battery-exempt) the moment the
 * app backgrounds. PiP is a SYSTEM-managed visible window — Android
 * keeps its process alive because the window is on screen, exactly
 * like a YouTube video floating over other apps. This is a genuinely
 * different mechanism from the overlay service, not another tweak.
 *
 * Flow: user taps "fix phone time" -> this activity opens full-screen
 * showing the atomic clock -> user taps "Settings کھولیں" -> activity
 * enters PiP and Date & Time settings opens -> PiP clock floats over
 * Settings. User sets the time looking at the PiP clock, then dismisses
 * PiP by dragging it away.
 */
class AtomicClockPipActivity : Activity() {

    companion object {
        const val EXTRA_OFFSET_MS = "offset_ms"
    }

    private var offsetMs: Long = 0L
    // v2.78: Set when the user taps "Settings کھولیں". Settings opens
    // ONLY after onPictureInPictureModeChanged confirms we are fully
    // in PiP — opening it immediately raced the PiP transition and
    // the system shrank Settings instead of our activity (v2.77 bug).
    private var openSettingsOnPip = false
    private var rootLayout: LinearLayout? = null
    private var timeText: TextView? = null
    private var dateText: TextView? = null
    private var buttonsRow: LinearLayout? = null
    private val handler = Handler(Looper.getMainLooper())

    private val tickTask = object : Runnable {
        override fun run() {
            updateDisplay()
            handler.postDelayed(this, 1000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        offsetMs = intent?.getLongExtra(EXTRA_OFFSET_MS, 0L) ?: 0L

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#1A1A1A"))
            setPadding(32, 32, 32, 32)
        }
        rootLayout = root
        timeText = TextView(this).apply {
            textSize = 32f
            setTextColor(Color.parseColor("#A3E635"))
            gravity = Gravity.CENTER
        }
        root.addView(timeText)
        dateText = TextView(this).apply {
            textSize = 14f
            setTextColor(Color.parseColor("#B3FFFFFF"))
            gravity = Gravity.CENTER
        }
        root.addView(dateText)

        buttonsRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(0, 32, 0, 0)
        }
        val settingsBtn = Button(this).apply {
            text = "Settings کھولیں"
            setOnClickListener { enterPipAndOpenSettings() }
        }
        buttonsRow?.addView(settingsBtn)
        val closeBtn = Button(this).apply {
            text = "بند کریں"
            setOnClickListener { finish() }
        }
        buttonsRow?.addView(closeBtn)
        root.addView(buttonsRow)

        setContentView(root)
        handler.post(tickTask)
    }

    override fun onDestroy() {
        handler.removeCallbacks(tickTask)
        super.onDestroy()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        // v2.80: PiP-optimized layout. Full-screen 32sp time wraps and
        // clips in the small PiP window (v2.79 showed only "PM").
        // In PiP: single-line smaller time, date hidden (only the time
        // matters while setting the clock), tight padding.
        if (isInPictureInPictureMode) {
            timeText?.apply {
                textSize = 22f
                setSingleLine(true)
            }
            dateText?.visibility = View.GONE
            rootLayout?.setPadding(16, 16, 16, 16)
        } else {
            timeText?.apply {
                textSize = 32f
                setSingleLine(false)
            }
            dateText?.visibility = View.VISIBLE
            rootLayout?.setPadding(32, 32, 32, 32)
        }
        // In PiP: clock only, no buttons (they don't fit the small window).
        buttonsRow?.visibility = if (isInPictureInPictureMode) View.GONE else View.VISIBLE
        // v2.78: PiP transition is COMPLETE here — now it is safe to
        // open Settings. Our activity is already small, so Settings
        // opens full-screen behind the PiP clock.
        if (isInPictureInPictureMode && openSettingsOnPip) {
            openSettingsOnPip = false
            try {
                // v2.79: NEW_TASK is REQUIRED — without it Settings joins
                // our PiP task and shows inside the small window.
                val si = Intent(Settings.ACTION_DATE_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(si)
            } catch (_: Exception) {
                // Best effort.
            }
        }
    }

    private fun updateDisplay() {
        val t = Date(System.currentTimeMillis() + offsetMs)
        timeText?.text = SimpleDateFormat("hh:mm:ss a", Locale.US).format(t)
        dateText?.text = SimpleDateFormat("d MMMM yyyy", Locale.US).format(t)
    }

    private fun enterPipAndOpenSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // v2.78: Enter PiP ONLY. Settings opens from
            // onPictureInPictureModeChanged once PiP is confirmed.
            openSettingsOnPip = true
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .build()
            val entered = enterPictureInPictureMode(params)
            if (!entered) {
                // PiP refused (e.g. disabled by OEM) — fall back to
                // plain Settings so the user is not stuck.
                openSettingsOnPip = false
                try {
                    val si = Intent(Settings.ACTION_DATE_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(si)
                } catch (_: Exception) {
                    // Best effort.
                }
            }
        } else {
            // Pre-Oreo: no PiP, just open Settings.
            try {
                val si = Intent(Settings.ACTION_DATE_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(si)
            } catch (_: Exception) {
                // Best effort.
            }
        }
    }
}
