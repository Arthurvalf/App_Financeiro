package com.arthurvalf.financa

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.text.NumberFormat
import java.util.Calendar
import java.util.Locale

/** Notificações do app. */
object Notify {
    private const val CHANNEL = "financa_geral"

    fun ensureChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT >= 26) {
            val nm = ctx.getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel(CHANNEL) == null) {
                val ch = NotificationChannel(CHANNEL, "Finança", NotificationManager.IMPORTANCE_DEFAULT)
                ch.description = "Gastos capturados, metas, parcelas e resumos"
                nm.createNotificationChannel(ch)
            }
        }
    }

    fun allowed(ctx: Context): Boolean {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return nm.areNotificationsEnabled()
    }

    fun openAppIntent(ctx: Context, requestCode: Int): PendingIntent {
        val intent = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
            ?: Intent(ctx, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(
            ctx, requestCode, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    fun show(ctx: Context, id: Int, title: String, body: String) {
        if (!allowed(ctx)) return
        ensureChannel(ctx)
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(ctx, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(ctx)
        }
        builder
            .setSmallIcon(R.drawable.ic_stat_financa)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(openAppIntent(ctx, id))
        if (Build.VERSION.SDK_INT >= 21) builder.setColor(0xFF111111.toInt())
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        try {
            nm.notify(id, builder.build())
        } catch (e: SecurityException) {
        }
    }
}

/** Lembretes agendados (parcelas, resumo semanal, dia do salário). */
object Reminders {
    private const val PREFS = "financa_reminders"

    fun schedule(ctx: Context, items: JSONArray) {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val old = JSONArray(prefs.getString("items", "[]"))
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (i in 0 until old.length()) {
            am.cancel(pending(ctx, old.getJSONObject(i)))
        }
        val now = System.currentTimeMillis()
        for (i in 0 until items.length()) {
            val it = items.getJSONObject(i)
            val at = it.getLong("at")
            if (at <= now) continue
            if (Build.VERSION.SDK_INT >= 23) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending(ctx, it))
            } else {
                am.set(AlarmManager.RTC_WAKEUP, at, pending(ctx, it))
            }
        }
        prefs.edit().putString("items", items.toString()).apply()
    }

    fun reschedule(ctx: Context) {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        schedule(ctx, JSONArray(prefs.getString("items", "[]")))
    }

    private fun pending(ctx: Context, item: JSONObject): PendingIntent {
        val intent = Intent(ctx, ReminderReceiver::class.java)
            .putExtra("id", item.optInt("id"))
            .putExtra("title", item.optString("title"))
            .putExtra("body", item.optString("body"))
        return PendingIntent.getBroadcast(
            ctx, item.optInt("id"), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Notify.show(
            context,
            intent.getIntExtra("id", 3999),
            intent.getStringExtra("title") ?: "Finança",
            intent.getStringExtra("body") ?: ""
        )
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) Reminders.reschedule(context)
    }
}

/** Dados exibidos no widget (escritos pelo app e atualizados pela captura). */
object WidgetData {
    const val PREFS = "financa_widget"
    private val money: NumberFormat = NumberFormat.getCurrencyInstance(Locale("pt", "BR"))

    fun fmt(v: Double): String = money.format(v)

    fun save(ctx: Context, data: Map<*, *>) {
        val e = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
        for ((k, v) in data) {
            val key = k.toString()
            when (v) {
                is Number -> e.putFloat(key, v.toFloat())
                null -> e.remove(key)
                else -> e.putString(key, v.toString())
            }
        }
        e.apply()
        FinancaWidget.refresh(ctx)
    }

    /** Soma um gasto capturado com o app fechado. */
    fun addExpense(ctx: Context, amount: Double) {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.contains("month")) return
        val c = Calendar.getInstance()
        val day = "${c.get(Calendar.YEAR)}-${c.get(Calendar.MONTH) + 1}-${c.get(Calendar.DAY_OF_MONTH)}"
        val monthKey = "${c.get(Calendar.YEAR)}-${c.get(Calendar.MONTH) + 1}"
        var today = if (prefs.getString("day", "") == day) prefs.getFloat("todayRaw", 0f).toDouble() else 0.0
        var month = if (prefs.getString("monthKey", "") == monthKey) prefs.getFloat("monthRaw", 0f).toDouble() else 0.0
        today += amount
        month += amount
        prefs.edit()
            .putString("day", day)
            .putString("monthKey", monthKey)
            .putFloat("todayRaw", today.toFloat())
            .putFloat("monthRaw", month.toFloat())
            .putString("today", fmt(today))
            .putString("month", fmt(month))
            .apply()
        FinancaWidget.refresh(ctx)
    }
}

class FinancaWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, render(context))
    }

    companion object {
        fun refresh(ctx: Context) {
            val manager = AppWidgetManager.getInstance(ctx)
            val ids = manager.getAppWidgetIds(ComponentName(ctx, FinancaWidget::class.java))
            if (ids.isNotEmpty()) {
                for (id in ids) manager.updateAppWidget(id, render(ctx))
            }
        }

        fun render(ctx: Context): RemoteViews {
            val p = ctx.getSharedPreferences(WidgetData.PREFS, Context.MODE_PRIVATE)
            val c = Calendar.getInstance()
            val day = "${c.get(Calendar.YEAR)}-${c.get(Calendar.MONTH) + 1}-${c.get(Calendar.DAY_OF_MONTH)}"
            val monthKey = "${c.get(Calendar.YEAR)}-${c.get(Calendar.MONTH) + 1}"
            val today = if (p.getString("day", "") == day) p.getString("today", null) ?: WidgetData.fmt(0.0) else WidgetData.fmt(0.0)
            val month = if (p.getString("monthKey", "") == monthKey) p.getString("month", null) ?: "—" else WidgetData.fmt(0.0)
            val label = p.getString("monthLabel", null) ?: "Este mês"
            val forecast = p.getString("forecast", null)
            val budgetLeft = p.getString("budgetLeft", "") ?: ""

            val v = RemoteViews(ctx.packageName, R.layout.financa_widget)
            v.setTextViewText(R.id.w_label, "Gastos de ${label.lowercase(Locale("pt", "BR"))}")
            v.setTextViewText(R.id.w_month, month)
            v.setTextViewText(R.id.w_today, "Hoje: $today")
            v.setTextViewText(
                R.id.w_extra,
                when {
                    budgetLeft.isNotEmpty() -> "Restam $budgetLeft nas metas"
                    forecast != null -> "Previsão: $forecast"
                    else -> "Abra o app para atualizar"
                }
            )
            v.setOnClickPendingIntent(R.id.w_root, Notify.openAppIntent(ctx, 77))
            return v
        }
    }
}
