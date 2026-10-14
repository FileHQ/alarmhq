package com.technoon.alarmhq

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.view.GestureDetector
import android.view.Gravity
import android.view.MotionEvent
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.Space
import android.widget.TextView
import android.widget.Toast
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import kotlin.math.abs

/**
 * Full-screen UI shown when an alarm fires — Realme/Samsung style:
 * huge time, date + weekday + AM/PM, label, big Snooze / Dismiss buttons.
 * Swipe UP = snooze, swipe DOWN = dismiss. Visible over the lock screen.
 */
class FullScreenAlarmActivity : Activity() {

    private lateinit var gestureDetector: GestureDetector
    private var alarmId: Int = -1
    private var alarmJsonStr: String = "{}"
    private var snoozeCount: Int = 0
    private var snoozeMinutes: Int = 10
    private var maxSnoozes: Int = 3
    private var canSnooze: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }

        val alarmJson = intent.getStringExtra("alarmJson") ?: "{}"
        snoozeCount = intent.getIntExtra("snoozeCount", 0)
        val alarm = try { JSONObject(alarmJson) } catch (_: Exception) { JSONObject() }
        alarmId = alarm.optInt("id", -1)
        alarmJsonStr = alarmJson
        val label = alarm.optString("label", "")
        snoozeMinutes = alarm.optInt("snoozeMinutes", 10)
        maxSnoozes = alarm.optInt("maxSnoozes", 3)
        // maxSnoozes: 0 = no snooze, -1 = unlimited.
        canSnooze = maxSnoozes != 0 &&
            (maxSnoozes < 0 || snoozeCount < maxSnoozes)

        // 12-hour clock + date line, like the system alarm apps.
        val cal = Calendar.getInstance()
        val h12 = cal.get(Calendar.HOUR).let { if (it == 0) 12 else it }
        val minute = cal.get(Calendar.MINUTE)
        val ampm = if (cal.get(Calendar.AM_PM) == Calendar.AM) "AM" else "PM"
        val timeText = "%d:%02d".format(h12, minute)
        val dateText = SimpleDateFormat("MMM d", Locale.getDefault()).format(Date())
        val dayText = SimpleDateFormat("EEEE", Locale.getDefault()).format(Date())

        val lime = Color.parseColor("#A3E635")
        val charcoal = Color.parseColor("#23272E")
        val grayText = Color.parseColor("#B0B7C3")

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setBackgroundColor(charcoal)
            setPadding(48, 96, 48, 64)
        }

        // Bug fix (v2.4): respect system-bar insets so the huge time is not
        // cut off behind the status bar and the swipe hint is not hidden
        // behind the navigation bar on edge-to-edge devices.
        root.setOnApplyWindowInsetsListener { v, insets ->
            val top: Int
            val bottom: Int
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val bars = insets.getInsets(
                    android.view.WindowInsets.Type.systemBars())
                top = bars.top
                bottom = bars.bottom
            } else {
                @Suppress("DEPRECATION")
                top = insets.systemWindowInsetTop
                @Suppress("DEPRECATION")
                bottom = insets.systemWindowInsetBottom
            }
            v.setPadding(48, 96 + top, 48, 64 + bottom)
            insets
        }

        val timeView = TextView(this).apply {
            text = timeText
            textSize = 96f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        }
        val dateView = TextView(this).apply {
            text = "$dateText · $dayText · $ampm"
            textSize = 20f
            setTextColor(grayText)
            gravity = Gravity.CENTER
        }
        val labelView = TextView(this).apply {
            text = label.ifEmpty { getString(R.string.alarm) }
            textSize = 24f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(0, 16, 0, 0)
        }

        // v2.8 (final user design): clock slider — vertical track with a
        // draggable ⏰ knob in the center. Drag knob UP → Stop,
        // drag knob DOWN → Snooze. Tap = no action (must drag).
        val density = resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()

        val stopLabel = TextView(this).apply {
            text = "■ ${getString(R.string.dismiss)}  ↑"
            textSize = 18f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            setTextColor(lime)
            gravity = Gravity.CENTER
        }
        val snoozeLabel = TextView(this).apply {
            text = "⏰ ${getString(R.string.snooze)}  ↓"
            textSize = 18f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            visibility = if (canSnooze) android.view.View.VISIBLE
            else android.view.View.GONE
        }

        // Slider: FrameLayout holding the track + the draggable knob.
        val trackHeight = dp(340)
        val knobSize = dp(92)
        val slider = android.widget.FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, trackHeight
            ).apply { topMargin = dp(8); bottomMargin = dp(8) }
        }
        val track = android.view.View(this).apply {
            val trackW = dp(28)
            layoutParams = android.widget.FrameLayout.LayoutParams(
                trackW, trackHeight, Gravity.CENTER
            )
            background = android.graphics.drawable.GradientDrawable().apply {
                shape = android.graphics.drawable.GradientDrawable.RECTANGLE
                cornerRadius = dp(14).toFloat()
                setColor(Color.parseColor("#3A414C"))
            }
        }
        val knob = TextView(this).apply {
            text = "⏰"
            textSize = 44f
            gravity = Gravity.CENTER
            layoutParams = android.widget.FrameLayout.LayoutParams(
                knobSize, knobSize, Gravity.CENTER
            )
            background = resources.getDrawable(
                R.drawable.slider_knob, null)
            // Lime glow around the knob.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                elevation = dp(12).toFloat()
                outlineProvider = android.view.ViewOutlineProvider.BACKGROUND
            }
        }
        slider.addView(track)
        slider.addView(knob)

        // Drag the knob: up = stop, down = snooze, tap = nothing.
        val dragThreshold = dp(90).toFloat()
        var knobDownY = 0f
        var knobStartTrans = 0f
        var knobMoved = false
        // Clamp travel to the track (knob stays inside).
        val maxTravel = (trackHeight - knobSize) / 2f
        knob.setOnTouchListener { v, ev ->
            when (ev.action) {
                MotionEvent.ACTION_DOWN -> {
                    knobDownY = ev.rawY
                    knobStartTrans = v.translationY
                    knobMoved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dy = ev.rawY - knobDownY
                    if (abs(dy) > 12) knobMoved = true
                    v.translationY =
                        (knobStartTrans + dy).coerceIn(-maxTravel, maxTravel)
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    val totalDy = v.translationY - knobStartTrans
                    // Snap back first, then act.
                    v.animate().translationY(0f).setDuration(180).start()
                    if (knobMoved) {
                        if (totalDy < -dragThreshold) {
                            doDismiss() // dragged UP → stop
                        } else if (totalDy > dragThreshold) {
                            doSnooze() // dragged DOWN → snooze
                        }
                    }
                    // Tap = no action (must drag).
                    true
                }
                else -> false
            }
        }

        val sliderHint = TextView(this).apply {
            text = getString(R.string.slider_hint)
            textSize = 14f
            setTextColor(grayText)
            gravity = Gravity.CENTER
            setPadding(0, dp(12), 0, 0)
        }

        // Top→bottom: time, date, label, spacer,
        // STOP label, slider, SNOOZE label, hint.
        root.addView(timeView)
        root.addView(dateView)
        root.addView(labelView)
        root.addView(Space(this), LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        root.addView(stopLabel)
        // Center the slider horizontally.
        val sliderWrap = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            addView(slider)
        }
        root.addView(sliderWrap)
        if (canSnooze) root.addView(snoozeLabel)
        root.addView(sliderHint)
        root.addView(Space(this), LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 0.5f))
        setContentView(root)

        // Xiaomi-style gradient background.
        root.background = resources.getDrawable(
            R.drawable.alarm_bg_gradient, null)

        // Screen-level swipe kept as a shortcut: swipe UP = stop,
        // swipe DOWN = snooze.
        gestureDetector = GestureDetector(
            this,
            object : GestureDetector.SimpleOnGestureListener() {
                override fun onFling(
                    e1: MotionEvent?,
                    e2: MotionEvent,
                    velocityX: Float,
                    velocityY: Float,
                ): Boolean {
                    val y1 = e1?.y ?: e2.y
                    val x1 = e1?.x ?: e2.x
                    val dy = e2.y - y1
                    val dx = e2.x - x1
                    // Vertical fling: swipe up = stop, swipe down = snooze.
                    if (abs(dy) > abs(dx) && abs(dy) > 150 && abs(velocityY) > 200) {
                        if (dy < 0) doDismiss() else doSnooze()
                        return true
                    }
                    return false
                }
            })
    }

    /** Detects the swipe gesture anywhere on screen (buttons still work). */
    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        gestureDetector.onTouchEvent(ev)
        return super.dispatchTouchEvent(ev)
    }

    private fun doSnooze() {
        if (!canSnooze) {
            Toast.makeText(
                this, getString(R.string.no_more_snoozes), Toast.LENGTH_SHORT
            ).show()
            return
        }
        if (alarmId >= 0) {
            AlarmScheduler.scheduleSnooze(
                this, alarmId, alarmJsonStr, snoozeMinutes, snoozeCount + 1
            )
        }
        Toast.makeText(
            this, getString(R.string.snoozing_for, snoozeMinutes),
            Toast.LENGTH_SHORT
        ).show()
        stopAlarmService()
        finish()
    }

    private fun doDismiss() {
        stopAlarmService()
        finish()
    }

    private fun stopAlarmService() {
        val i = Intent(this, AlarmService::class.java).apply {
            action = AlarmService.ACTION_STOP
        }
        startService(i)
    }

    @Deprecated("Back button should not dismiss the alarm screen")
    override fun onBackPressed() {
        // Intentionally empty: the user must swipe or tap Dismiss/Snooze.
    }
}
