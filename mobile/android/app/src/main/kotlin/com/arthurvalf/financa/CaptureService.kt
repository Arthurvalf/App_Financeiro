package com.arthurvalf.financa

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject

/**
 * Escuta as notificações do app do Nubank e guarda numa fila local.
 * Funciona mesmo com o Finança fechado; quando o app abre, a fila vira lançamentos.
 */
class CaptureService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        if (sbn.packageName !in CaptureStore.PACKAGES) return
        val extras = sbn.notification?.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val big = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
        val text = (big ?: extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()).orEmpty()
        if (title.isBlank() && text.isBlank()) return
        // Ignora o "resumo" de notificações agrupadas
        if ((sbn.notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0) return
        CaptureStore.add(applicationContext, sbn.packageName, title, text, sbn.postTime)
    }
}

object CaptureStore {
    val PACKAGES = setOf("com.nu.production")

    private const val PREFS = "financa_capture"
    private const val QUEUE = "queue"
    private const val RECENT = "recent"
    private const val SEEN = "seen"

    @Synchronized
    fun add(ctx: Context, pkg: String, title: String, text: String, time: Long) {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        // Evita duplicar a mesma notificação (o Nubank às vezes atualiza a mesma)
        val signature = "$title|$text".hashCode().toString()
        val seen = JSONArray(prefs.getString(SEEN, "[]"))
        for (i in 0 until seen.length()) {
            val s = seen.getJSONObject(i)
            if (s.getString("sig") == signature && time - s.getLong("time") < 10 * 60 * 1000) return
        }
        seen.put(JSONObject().put("sig", signature).put("time", time))
        val item = JSONObject()
            .put("pkg", pkg)
            .put("title", title)
            .put("text", text)
            .put("time", time)
        val queue = JSONArray(prefs.getString(QUEUE, "[]")).put(item)
        val recent = JSONArray(prefs.getString(RECENT, "[]")).put(item)
        prefs.edit()
            .putString(QUEUE, trim(queue, 500).toString())
            .putString(RECENT, trim(recent, 30).toString())
            .putString(SEEN, trim(seen, 50).toString())
            .apply()
    }

    @Synchronized
    fun drain(ctx: Context): String {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val q = prefs.getString(QUEUE, "[]") ?: "[]"
        prefs.edit().putString(QUEUE, "[]").apply()
        return q
    }

    fun recent(ctx: Context): String {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val arr = JSONArray(prefs.getString(RECENT, "[]"))
        val reversed = JSONArray()
        for (i in arr.length() - 1 downTo 0) reversed.put(arr.get(i))
        return reversed.toString()
    }

    private fun trim(arr: JSONArray, max: Int): JSONArray {
        if (arr.length() <= max) return arr
        val out = JSONArray()
        for (i in arr.length() - max until arr.length()) out.put(arr.get(i))
        return out
    }
}
