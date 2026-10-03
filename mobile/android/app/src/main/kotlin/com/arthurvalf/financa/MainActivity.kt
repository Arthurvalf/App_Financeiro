package com.arthurvalf.financa

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Notify.ensureChannel(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "financa/capture").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "isEnabled" -> result.success(isListenerEnabled())
                    "openSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(null)
                    }
                    "openAppInfo" -> {
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(null)
                    }
                    "drain" -> result.success(CaptureStore.drain(applicationContext))
                    "recent" -> result.success(CaptureStore.recent(applicationContext))
                    "updateWidget" -> {
                        val data = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                        WidgetData.save(applicationContext, data)
                        result.success(null)
                    }
                    "notify" -> {
                        Notify.show(
                            applicationContext,
                            call.argument<Int>("id") ?: 1,
                            call.argument<String>("title") ?: "Finança",
                            call.argument<String>("body") ?: ""
                        )
                        result.success(null)
                    }
                    "schedule" -> {
                        val items = call.argument<List<Map<String, Any?>>>("items") ?: emptyList()
                        val arr = JSONArray()
                        for (m in items) {
                            val o = JSONObject()
                            o.put("id", (m["id"] as? Number)?.toInt() ?: 0)
                            o.put("at", (m["at"] as? Number)?.toLong() ?: 0L)
                            o.put("title", m["title"]?.toString() ?: "")
                            o.put("body", m["body"]?.toString() ?: "")
                            arr.put(o)
                        }
                        Reminders.schedule(applicationContext, arr)
                        result.success(null)
                    }
                    "notificationsAllowed" -> result.success(Notify.allowed(applicationContext))
                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT >= 33) {
                            requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"), 42)
                        }
                        result.success(null)
                    }
                    "setFlag" -> {
                        applicationContext.getSharedPreferences("financa_flags", Context.MODE_PRIVATE).edit()
                            .putBoolean(call.argument<String>("key") ?: "", call.argument<Boolean>("value") ?: true)
                            .apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("native_error", e.message, null)
            }
        }
    }

    private fun isListenerEnabled(): Boolean {
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
        val me = ComponentName(this, CaptureService::class.java)
        return flat.split(":").any { ComponentName.unflattenFromString(it) == me }
    }
}
