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

        val dismissBtn = Button(this).apply {
            text = getString(R.string.dismiss)
            textSize = 22f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            setTextColor(Color.BLACK)
            setBackgroundColor(lime)
        }
        val snoozeBtn = Button(this).apply {
            text = if (maxSnoozes > 0)
                "${getString(R.string.snooze)} (${snoozeCount + 1}/$maxSnoozes)"
            else getString(R.string.snooze)
            textSize = 22f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.parseColor("#3A414C"))
            visibility = if (canSnooze) android.view.View.VISIBLE
            else android.view.View.GONE
        }

        dismissBtn.setOnClickListener { doDismiss() }
        snoozeBtn.setOnClickListener { doSnooze() }

        val btnParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply {
            topMargin = 20
            height = 176
        }

        val hintView = TextView(this).apply {
            text = getString(R.string.swipe_hints)
            textSize = 14f
            setTextColor(grayText)
            gravity = Gravity.CENTER
            setPadding(0, 28, 0, 0)
        }

        root.addView(timeView)
        root.addView(dateView)
        root.addView(labelView)
        root.addView(Space(this), LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        root.addView(dismissBtn, btnParams)
        root.addView(snoozeBtn, btnParams)
        root.addView(hintView)
        setContentView(root)

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
                    // Vertical fling: swipe up = snooze, swipe down = dismiss.
                    if (abs(dy) > abs(dx) && abs(dy) > 150 && abs(velocityY) > 200) {
                        if (dy < 0) doSnooze() else doDismiss()
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
