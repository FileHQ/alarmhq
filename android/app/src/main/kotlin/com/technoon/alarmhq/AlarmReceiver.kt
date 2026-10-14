package com.technoon.alarmhq

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/** Fired by AlarmManager when an alarm (or a snooze one-shot) goes off. */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val alarmJson = intent.getStringExtra("alarmJson") ?: return
        val snoozeCount = intent.getIntExtra("snoozeCount", 0)
        val isSnooze = intent.getBooleanExtra("isSnooze", false)

        // Arm the following regular occurrence first, so it survives even if
        // the service below fails to start. Snooze one-shots skip this.
        if (!isSnooze) AlarmScheduler.onFired(context, alarmJson)

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
        AlarmScheduler.updateWidget(context)
    }
}
