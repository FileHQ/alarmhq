package com.technoon.alarmhq

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/** Fired by AlarmManager when an alarm (or a snooze one-shot) goes off. */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // v2.15: diagnostic logging to trace firing issues.
        android.util.Log.i("AlarmHQ", "AlarmReceiver.onReceive: fired!")
        val alarmJson = intent.getStringExtra("alarmJson") ?: run {
            android.util.Log.w("AlarmHQ", "AlarmReceiver: missing alarmJson, aborting")
            return
        }
        val snoozeCount = intent.getIntExtra("snoozeCount", 0)
        val isSnooze = intent.getBooleanExtra("isSnooze", false)
        val alarmId = intent.getIntExtra("alarmId", -1)

        // Arm the following regular occurrence first, so it survives even if
        // the service below fails to start. Snooze one-shots skip this.
        if (!isSnooze) AlarmScheduler.onFired(context, alarmJson)

        // v2.4: a fired snooze is no longer "pending" — clear its trigger so
        // the UI countdown falls back to the next regular occurrence.
        if (isSnooze && alarmId >= 0) {
            AlarmScheduler.clearSnoozeTrigger(context, alarmId)
        }

        val svc = Intent(context, AlarmService::class.java).apply {
            action = AlarmService.ACTION_START
            putExtra("alarmJson", alarmJson)
            putExtra("snoozeCount", snoozeCount)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(svc)
        } else {
            context.startService(svc)
        }

        // Launch the full-screen alarm UI (over the lock screen). Without
        // this the alarm rings with no visible screen.
        val fullScreen = Intent(context, FullScreenAlarmActivity::class.java).apply {
            putExtra("alarmJson", alarmJson)
            putExtra("snoozeCount", snoozeCount)
            // v2.21: alarmId fallback for doSnooze when the JSON lacks it.
            putExtra("alarmId", alarmId)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        try {
            context.startActivity(fullScreen)
        } catch (_: Exception) {
            // Activity launch failed (e.g. background-start restriction);
            // the AlarmService keeps ringing and the full-screen notification
            // intent still offers a way in.
        }
        AlarmScheduler.updateWidget(context)
    }
}
