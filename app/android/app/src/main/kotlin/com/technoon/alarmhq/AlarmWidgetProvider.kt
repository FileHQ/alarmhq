package com.technoon.alarmhq

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/** Home-screen widget showing the next alarm time. */
class AlarmWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray
    ) {
        updateAll(context)
    }

    companion object {
        fun refresh(context: Context) = updateAll(context)

        private fun updateAll(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(
                ComponentName(context, AlarmWidgetProvider::class.java)
            )
            if (ids.isEmpty()) return
            val text = AlarmScheduler.getNextText(context)
            val views = RemoteViews(context.packageName, R.layout.alarm_widget).apply {
                setTextViewText(
                    R.id.widget_next,
                    text.ifEmpty { context.getString(R.string.no_alarms_set) },
                )
            }
            val open = PendingIntent.getActivity(
                context, 0,
                Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, open)
            for (id in ids) mgr.updateAppWidget(id, views)
        }
    }
}
