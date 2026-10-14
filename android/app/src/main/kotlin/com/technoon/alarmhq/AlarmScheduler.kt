package com.technoon.alarmhq

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * Owns all native alarm scheduling. Mirrors the Dart NextOccurrence math
 * (lib/services/next_occurrence.dart) — both sides must agree.
 *
 * Alarm definitions are stored natively (alarm JSON per id) so repeats keep
 * working and survive reboots without the Flutter engine running.
 */
object AlarmScheduler {
    private const val DEFS = "alarmhq_native_defs"
    private const val MISC = "alarmhq_native_misc"
    private const val KEY_NEXT_TEXT = "next_text"

    private fun defsPrefs(context: Context) =
        context.getSharedPreferences(DEFS, Context.MODE_PRIVATE)

    private fun miscPrefs(context: Context) =
        context.getSharedPreferences(MISC, Context.MODE_PRIVATE)

    // ---------- definition storage ----------

    fun storeDef(context: Context, id: Int, alarmJson: String) {
        defsPrefs(context).edit().putString("alarm_$id", alarmJson).apply()
    }

    fun removeDef(context: Context, id: Int) {
        defsPrefs(context).edit().remove("alarm_$id").apply()
    }

    fun getDef(context: Context, id: Int): JSONObject? {
        val s = defsPrefs(context).getString("alarm_$id", null) ?: return null
        return try { JSONObject(s) } catch (_: Exception) { null }
    }

    fun allDefs(context: Context): List<JSONObject> {
        val out = mutableListOf<JSONObject>()
        for ((k, v) in defsPrefs(context).all) {
            if (k.startsWith("alarm_") && v is String) {
                try { out.add(JSONObject(v)) } catch (_: Exception) { /* skip */ }
            }
        }
        return out
    }

    // ---------- next-trigger math (mirrors Dart) ----------

    /** Next ring epoch-ms at/after [nowMillis], or null when none. */
    fun nextTriggerMillis(alarm: JSONObject, nowMillis: Long): Long? {
        val hour = alarm.optInt("hour", 7)
        val minute = alarm.optInt("minute", 0)
        val t = when (alarm.optString("mode", "weekly")) {
            "weekly" -> nextWeekly(alarm, hour, minute, nowMillis)
            "once" -> nextOnce(alarm, hour, minute, nowMillis)
            "interval" -> nextInterval(alarm, hour, minute, nowMillis)
            "specificDates" -> nextSpecificDates(alarm, hour, minute, nowMillis)
            else -> null
        }
        // "Skip next only": if the computed trigger matches skipNextDate,
        // find the following one instead.
        val skipStr = alarm.optString("skipNextDate", null)
        if (t != null && skipStr != null) {
            val skipCal = parseDateTime(skipStr)
            if (skipCal != null && t == skipCal.timeInMillis) {
                return nextTriggerMillisAfter(alarm, hour, minute, t + 1000)
            }
        }
        return t
    }

    private fun nextTriggerMillisAfter(
        alarm: JSONObject, hour: Int, minute: Int, afterMillis: Long
    ): Long? {
        return when (alarm.optString("mode", "weekly")) {
            "weekly" -> nextWeekly(alarm, hour, minute, afterMillis)
            "once" -> nextOnce(alarm, hour, minute, afterMillis)
            "interval" -> nextInterval(alarm, hour, minute, afterMillis)
            "specificDates" -> nextSpecificDates(alarm, hour, minute, afterMillis)
            else -> null
        }
    }

    private fun atMillis(day: Calendar, hour: Int, minute: Int): Long {
        val c = day.clone() as Calendar
        c.set(Calendar.HOUR_OF_DAY, hour)
        c.set(Calendar.MINUTE, minute)
        c.set(Calendar.SECOND, 0)
        c.set(Calendar.MILLISECOND, 0)
        return c.timeInMillis
    }

    /** Dart weekday 1=Mon..7=Sun -> Calendar DAY_OF_WEEK. */
    private fun dartWdToCalendar(wd: Int): Int = (wd % 7) + 1

    private fun nextWeekly(
        alarm: JSONObject, hour: Int, minute: Int, nowMillis: Long
    ): Long? {
        val days = alarm.optJSONArray("weekDays") ?: JSONArray()
        if (days.length() == 0) return null
        var best: Long? = null
        val today = Calendar.getInstance()
        for (i in 0 until days.length()) {
            val target = dartWdToCalendar(days.optInt(i, 1))
            val current = today.get(Calendar.DAY_OF_WEEK)
            val delta = (target - current + 7) % 7
            val c = today.clone() as Calendar
            c.add(Calendar.DAY_OF_YEAR, delta)
            var cand = atMillis(c, hour, minute)
            if (cand < nowMillis) cand += 7L * 24 * 60 * 60 * 1000
            if (best == null || cand < best) best = cand
        }
        return best
    }

    private fun nextOnce(
        alarm: JSONObject, hour: Int, minute: Int, nowMillis: Long
    ): Long? {
        val ds = alarm.optString("onceDate", null) ?: return null
        val c = parseDate(ds) ?: return null
        val t = atMillis(c, hour, minute)
        return if (t < nowMillis) null else t
    }

    private fun nextInterval(
        alarm: JSONObject, hour: Int, minute: Int, nowMillis: Long
    ): Long? {
        val n = alarm.optInt("intervalDays", 1)
        if (n < 1) return null
        val ds = alarm.optString("intervalStart", null) ?: return null
        val origin = atMillis(parseDate(ds) ?: return null, hour, minute)
        if (origin >= nowMillis) return origin
        val step = n.toLong() * 24 * 60 * 60 * 1000
        val elapsed = nowMillis - origin
        val k = (elapsed + step - 1) / step // ceil
        return origin + k * step
    }

    private fun nextSpecificDates(
        alarm: JSONObject, hour: Int, minute: Int, nowMillis: Long
    ): Long? {
        val arr = alarm.optJSONArray("specificDates") ?: return null
        var best: Long? = null
        for (i in 0 until arr.length()) {
            val c = parseDate(arr.optString(i, "")) ?: continue
            val t = atMillis(c, hour, minute)
            if (t < nowMillis) continue
            if (best == null || t < best) best = t
        }
        return best
    }

    private fun parseDate(s: String): Calendar? {
        return try {
            val p = s.split("-").map { it.toInt() }
            Calendar.getInstance().apply {
                set(Calendar.YEAR, p[0])
                set(Calendar.MONTH, p[1] - 1)
                set(Calendar.DAY_OF_MONTH, p[2])
            }
        } catch (_: Exception) { null }
    }

    /** Parse "yyyy-MM-ddTHH:mm" (skipNextDate). */
    private fun parseDateTime(s: String): Calendar? {
        return try {
            val parts = s.split("T")
            val d = parts[0].split("-").map { it.toInt() }
            val t = parts[1].split(":").map { it.toInt() }
            Calendar.getInstance().apply {
                set(Calendar.YEAR, d[0])
                set(Calendar.MONTH, d[1] - 1)
                set(Calendar.DAY_OF_MONTH, d[2])
                set(Calendar.HOUR_OF_DAY, t[0])
                set(Calendar.MINUTE, t[1])
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
        } catch (_: Exception) { null }
    }

    // ---------- scheduling ----------

    private fun alarmManager(context: Context) =
        context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    private fun fireIntent(
        context: Context, id: Int, alarmJson: String, snoozeCount: Int,
        isSnooze: Boolean
    ): PendingIntent {
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra("alarmId", id)
            putExtra("alarmJson", alarmJson)
            putExtra("snoozeCount", snoozeCount)
            putExtra("isSnooze", isSnooze)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        // Unique request code per alarm (+1 for snooze one-shots).
        val rc = if (isSnooze) id * 10 + 7 else id
        return PendingIntent.getBroadcast(context, rc, intent, flags)
    }

    private fun showIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getActivity(context, 0, intent, flags)
    }

    fun canScheduleExact(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            alarmManager(context).canScheduleExactAlarms()
        } else true
    }

    /** Arm [triggerAtMillis] for alarm [id]. Returns false when exact-alarm
     *  permission is missing on Android 12+. */
    fun schedule(
        context: Context, id: Int, triggerAtMillis: Long, alarmJson: String
    ): Boolean {
        if (!canScheduleExact(context)) return false
        storeDef(context, id, alarmJson)
        val am = alarmManager(context)
        val info = AlarmManager.AlarmClockInfo(triggerAtMillis, showIntent(context))
        am.setAlarmClock(info, fireIntent(context, id, alarmJson, 0, false))
        updateWidget(context)
        return true
    }

    fun scheduleSnooze(
        context: Context, id: Int, alarmJson: String,
        snoozeMinutes: Int, snoozeCount: Int
    ) {
        if (!canScheduleExact(context)) return
        val trigger = System.currentTimeMillis() + snoozeMinutes * 60_000L
        val am = alarmManager(context)
        val info = AlarmManager.AlarmClockInfo(trigger, showIntent(context))
        am.setAlarmClock(
            info, fireIntent(context, id, alarmJson, snoozeCount, true)
        )
    }

    fun cancel(context: Context, id: Int) {
        val am = alarmManager(context)
        // Cancel both the regular and any snooze pending intents.
        am.cancel(fireIntent(context, id, "{}", 0, false))
        am.cancel(fireIntent(context, id, "{}", 0, true))
        removeDef(context, id)
        updateWidget(context)
    }

    fun cancelAll(context: Context) {
        for (def in allDefs(context)) cancel(context, def.optInt("id", -1))
    }

    /** Called by AlarmReceiver right when an alarm fires: arm the following
     *  occurrence (or retire a one-time alarm). */
    fun onFired(context: Context, alarmJson: String) {
        val alarm = try { JSONObject(alarmJson) } catch (_: Exception) { return }
        val id = alarm.optInt("id", -1)
        if (id < 0) return
        val next = nextTriggerMillis(alarm, System.currentTimeMillis())
        if (next == null) {
            // One-time alarm in the past, or weekly with no days: retire it.
            val retired = JSONObject(alarmJson).put("enabled", false)
            storeDef(context, id, retired.toString())
        } else {
            // Re-arm the stored def at its next occurrence.
            val am = alarmManager(context)
            if (canScheduleExact(context)) {
                val info = AlarmManager.AlarmClockInfo(next, showIntent(context))
                am.setAlarmClock(info, fireIntent(context, id, alarmJson, 0, false))
            }
        }
        updateWidget(context)
    }

    /** Re-arm every enabled stored alarm (boot). */
    fun rescheduleAllFromDefs(context: Context) {
        if (!canScheduleExact(context)) return
        val now = System.currentTimeMillis()
        for (alarm in allDefs(context)) {
            if (!alarm.optBoolean("enabled", true)) continue
            val id = alarm.optInt("id", -1)
            if (id < 0) continue
            val next = nextTriggerMillis(alarm, now) ?: continue
            val am = alarmManager(context)
            val info = AlarmManager.AlarmClockInfo(next, showIntent(context))
            am.setAlarmClock(info, fireIntent(context, id, alarm.toString(), 0, false))
        }
        updateWidget(context)
    }

    // ---------- widget ----------

    fun setNextText(context: Context, text: String) {
        miscPrefs(context).edit().putString(KEY_NEXT_TEXT, text).apply()
        AlarmWidgetProvider.refresh(context)
    }

    fun getNextText(context: Context): String =
        miscPrefs(context).getString(KEY_NEXT_TEXT, "") ?: ""

    /** Recompute the widget text from stored defs (native side). */
    fun updateWidget(context: Context) {
        val now = System.currentTimeMillis()
        var best: Long? = null
        for (alarm in allDefs(context)) {
            if (!alarm.optBoolean("enabled", true)) continue
            val t = nextTriggerMillis(alarm, now) ?: continue
            if (best == null || t < best) best = t
        }
        val text = if (best == null) "" else {
            val c = Calendar.getInstance().apply { timeInMillis = best!! }
            val hh = c.get(Calendar.HOUR_OF_DAY).toString().padStart(2, '0')
            val mm = c.get(Calendar.MINUTE).toString().padStart(2, '0')
            val wd = arrayOf("", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")[
                (c.get(Calendar.DAY_OF_WEEK) + 5) % 7 + 1
            ]
            "$wd $hh:$mm"
        }
        setNextText(context, text)
    }
}
