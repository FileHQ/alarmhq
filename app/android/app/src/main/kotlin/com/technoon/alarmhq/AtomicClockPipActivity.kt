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
import android.os.SystemClock
import android.provider.Settings
import android.util.Rational
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
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
        // v2.85: app language ('en'/'ur') — the PiP buttons were
        // hardcoded Urdu and ignored English mode entirely.
        const val EXTRA_LANG = "lang"
    }

    private var offsetMs: Long = 0L
    private var isUrdu: Boolean = false
    // v2.85: monotonic anchor — the old clock was deviceTime +
    // snapshot offset, so when the user changed the phone time in
    // Settings the PiP followed the phone and went wrong. Anchoring
    // to elapsedRealtime (immune to wall-clock changes) keeps the
    // PiP on true atomic time no matter what the phone is set to.
    private var anchorAtomicMs: Long = 0L
    private var anchorElapsedMs: Long = 0L
    // v2.78: Set when the user taps "Settings کھولیں". Settings opens
    // ONLY after onPictureInPictureModeChanged confirms we are fully
    // in PiP — opening it immediately raced the PiP transition and
    // the system shrank Settings instead of our activity (v2.77 bug).
    private var openSettingsOnPip = false
    private var rootLayout: LinearLayout? = null
    private var timeText: TextView? = null
    private var dateText: TextView? = null
    private var buttonsRow: LinearLayout? = null
    // v2.83 fallback chain: PiP -> overlay -> note-the-time.
    private var overlayStarted = false
    private var noteFallback = false
    private var noticeText: TextView? = null
    private var settingsBtn: Button? = null
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
        isUrdu = intent?.getStringExtra(EXTRA_LANG) == "ur"
        anchorAtomicMs = System.currentTimeMillis() + offsetMs
        anchorElapsedMs = SystemClock.elapsedRealtime()

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
        // v2.83: shown only in the note-the-time fallback (no PiP,
        // no overlay) — explains why no floating clock will appear.
        noticeText = TextView(this).apply {
            text = if (isUrdu) {
                "اس موبائل میں چھوٹی window دستیاب نہیں ہے۔ اوپر والا ٹائم نوٹ کر لیں، پھر Settings کھول کر وہی ٹائم لگائیں۔"
            } else {
                "This phone doesn't support a small window. Note the time above, then open Settings and set the same time."
            }
            textSize = 14f
            setTextColor(Color.parseColor("#B3FFFFFF"))
            gravity = Gravity.CENTER
            visibility = View.GONE
            setPadding(32, 24, 32, 0)
        }
        root.addView(noticeText)

        buttonsRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(0, 32, 0, 0)
        }
        settingsBtn = Button(this).apply {
            // v2.87: fully Urdu on the Urdu screen ("سیٹنگز" matches
            // the app's own Urdu term) — no mixed English word.
            text = if (isUrdu) "سیٹنگز کھولیں" else "Open Settings"
            setOnClickListener { enterPipAndOpenSettings() }
        }
        buttonsRow?.addView(settingsBtn)
        val closeBtn = Button(this).apply {
            text = if (isUrdu) "بند کریں" else "Close"
            setOnClickListener {
                // v2.83: stop a fallback overlay so no orphan clock
                // floats after the user closes this screen.
                if (overlayStarted) {
                    try {
                        stopService(
                            Intent(
                                this@AtomicClockPipActivity,
                                AtomicOverlayNativeService::class.java,
                            ),
                        )
                    } catch (_: Exception) {
                    }
                }
                finish()
            }
        }
        buttonsRow?.addView(closeBtn)
        root.addView(buttonsRow)

        setContentView(root)
        handler.post(tickTask)
    }

    override fun onDestroy() {
        handler.removeCallbacks(tickTask)
        // v2.83: system Back also finishes — stop a fallback overlay
        // then too (isFinishing is false on rotation, so a config
        // change does not kill an overlay the user is still using).
        if (overlayStarted && isFinishing) {
            try {
                stopService(Intent(this, AtomicOverlayNativeService::class.java))
            } catch (_: Exception) {
            }
        }
        super.onDestroy()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        // v2.80: PiP-optimized layout. Full-screen 32sp time wraps and
        // clips in the small PiP window (v2.79 showed only "PM").
        // v2.81: time was one line but its TOP was cut by the system
        // tap-label ("AlarmHQ" bar) — so in PiP the time now sits
        // BELOW the label zone (large top padding) in a taller window.
        // In PiP: single-line time, date hidden (only the time
        // matters while setting the clock).
        if (isInPictureInPictureMode) {
            timeText?.apply {
                textSize = 24f
                setSingleLine(true)
            }
            dateText?.visibility = View.GONE
            val d = resources.displayMetrics.density
            // Top padding pushes time below the system label zone.
            rootLayout?.setPadding(
                (16 * d).toInt(), (64 * d).toInt(),
                (16 * d).toInt(), (16 * d).toInt(),
            )
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
        // v2.85: monotonic anchor (see fields) — wall-clock changes
        // from Settings no longer move this clock.
        val t = Date(
            anchorAtomicMs +
                (SystemClock.elapsedRealtime() - anchorElapsedMs),
        )
        timeText?.text = SimpleDateFormat("hh:mm:ss a", Locale.US).format(t)
        dateText?.text = SimpleDateFormat("d MMMM yyyy", Locale.US).format(t)
    }

    // v2.83 fallback chain, in order:
    //  1. PiP (system window; best on modern phones).
    //  2. Overlay service (needs SYSTEM_ALERT_WINDOW; works where
    //     PiP does not exist, e.g. older Android with looser rules).
    //  3. Note-the-time screen (always works: clock stays visible
    //     here, user notes it, then opens plain Settings).
    private fun enterPipAndOpenSettings() {
        // Already in note-time mode: this tap just opens Settings.
        if (noteFallback) {
            openPlainSettings()
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // v2.78: Enter PiP ONLY. Settings opens from
            // onPictureInPictureModeChanged once PiP is confirmed.
            openSettingsOnPip = true
            // v2.81: 4:3 (taller) — 16:9 was too short; the system tap
            // label ("AlarmHQ" bar) covered the top of the time.
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(4, 3))
                .build()
            val entered = enterPictureInPictureMode(params)
            if (entered) return
            // PiP refused (e.g. disabled by OEM) — try overlay below.
            openSettingsOnPip = false
        }
        // PiP unavailable (pre-Oreo) or refused: try overlay.
        if (Settings.canDrawOverlays(this)) {
            try {
                val intent = Intent(this, AtomicOverlayNativeService::class.java).apply {
                    putExtra(AtomicOverlayNativeService.EXTRA_OFFSET_MS, offsetMs)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(intent)
                } else {
                    startService(intent)
                }
                overlayStarted = true
                // This screen stays behind Settings, so Back returns
                // here (recovery if the overlay itself gets killed).
                Toast.makeText(
                    this,
                    if (isUrdu) {
                        "تیرتی گھڑی چل رہی ہے — اگر Settings پر نظر نہ آئے تو Back دبا کر ٹائم نوٹ کر لیں"
                    } else {
                        "Floating clock is running — if it doesn't appear over Settings, press Back and note the time"
                    },
                    Toast.LENGTH_LONG,
                ).show()
                openPlainSettings()
                return
            } catch (_: Exception) {
                // Fall through to note-the-time.
            }
        }
        // Overlay also unavailable (no permission / failed):
        // note-the-time fallback — clock stays visible here.
        noteFallback = true
        noticeText?.visibility = View.VISIBLE
    }

    private fun openPlainSettings() {
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
