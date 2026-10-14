package com.technoon.alarmhq

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONObject
import java.util.Calendar

/**
 * Full-screen UI shown when an alarm fires — big Dismiss / Snooze buttons,
 * visible over the lock screen.
 */
class FullScreenAlarmActivity : Activity() {

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
        val snoozeCount = intent.getIntExtra("snoozeCount", 0)
        val alarm = try { JSONObject(alarmJson) } catch (_: Exception) { JSONObject() }
        val id = alarm.optInt("id", -1)
        val label = alarm.optString("label", "")
        val snoozeMinutes = alarm.optInt("snoozeMinutes", 10)
        val maxSnoozes = alarm.optInt("maxSnoozes", 3)
        val canSnooze = maxSnoozes > 0 && snoozeCount < maxSnoozes

        val now = Calendar.getInstance()
        val timeText = "%02d:%02d".format(
            now.get(Calendar.HOUR_OF_DAY), now.get(Calendar.MINUTE)
        )

        val emerald = Color.parseColor("#10B981")
        val charcoal = Color.parseColor("#23272E")

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(charcoal)
            setPadding(48, 48, 48, 48)
        }

        val timeView = TextView(this).apply {
            text = timeText
            textSize = 84f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        }
        val labelView = TextView(this).apply {
            text = label.ifEmpty { getString(R.string.alarm) }
            textSize = 24f
            setTextColor(Color.parseColor("#B0B7C3"))
            gravity = Gravity.CENTER
        }
        val dismissBtn = Button(this).apply {
            text = getString(R.string.dismiss)
            textSize = 22f
            setTextColor(Color.WHITE)
            setBackgroundColor(emerald)
        }
        val snoozeBtn = Button(this).apply {
            text = if (maxSnoozes > 0)
                "${getString(R.string.snooze)} (${snoozeCount + 1}/$maxSnoozes)"
            else getString(R.string.snooze)
            textSize = 22f
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.parseColor("#3A414C"))
            visibility = if (canSnooze) android.view.View.VISIBLE
            else android.view.View.GONE
        }

        dismissBtn.setOnClickListener {
            stopAlarmService()
            finish()
        }
        snoozeBtn.setOnClickListener {
            if (id >= 0) {
                AlarmScheduler.scheduleSnooze(
                    this, id, alarmJson, snoozeMinutes, snoozeCount + 1
                )
            }
            stopAlarmService()
            finish()
        }

        val btnParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply {
            topMargin = 24
            height = 168
        }

        root.addView(timeView)
        root.addView(labelView)
        root.addView(dismissBtn, btnParams)
        root.addView(snoozeBtn, btnParams)
        setContentView(root)
    }

    private fun stopAlarmService() {
        val i = Intent(this, AlarmService::class.java).apply {
            action = AlarmService.ACTION_STOP
        }
        startService(i)
    }

    @Deprecated("Back button should not dismiss the alarm screen")
    override fun onBackPressed() {
        // Intentionally empty: the user must tap Dismiss or Snooze.
    }
}
