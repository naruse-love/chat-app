package com.example.chat

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL_NAME = "com.example.chat/persistent_notification"
        private const val NOTIFICATION_CHANNEL_ID = "chat_persistent_shortcuts"
        private const val NOTIFICATION_CHANNEL_NAME = "常驻快捷入口"
        private const val NOTIFICATION_ID_BASE = 9988
    }

    private var methodChannel: MethodChannel? = null
    private var launchPayload: String? = null
    private val activeNotifications = mutableSetOf<String>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val payload = intent.getStringExtra("payload")
            ?: (if (intent.action == "com.example.chat.ACTION_VOCABULARY") "/vocabulary" else null)

        if (payload != null) {
            launchPayload = payload
            methodChannel?.invokeMethod("onNotificationTapped", payload)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        methodChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "showPersistentNotification" -> {
                    val id = call.argument<String>("id") ?: "vocab_shortcut"
                    val title = call.argument<String>("title") ?: "📚 日语生词快捷查询"
                    val body = call.argument<String>("body") ?: "点击快速打开单词查询"
                    val payload = call.argument<String>("payload") ?: "/vocabulary"

                    try {
                        showNotification(id, title, body, payload)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("NOTIFICATION_ERROR", e.message, null)
                    }
                }
                "cancelPersistentNotification" -> {
                    val id = call.argument<String>("id") ?: "vocab_shortcut"
                    try {
                        cancelNotification(id)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("NOTIFICATION_ERROR", e.message, null)
                    }
                }
                "isNotificationActive" -> {
                    val id = call.argument<String>("id") ?: "vocab_shortcut"
                    result.success(activeNotifications.contains(id))
                }
                "getLaunchPayload" -> {
                    val p = launchPayload
                    launchPayload = null
                    result.success(p)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                NOTIFICATION_CHANNEL_NAME,
                importance
            ).apply {
                description = "应用快捷常驻通知，用于快速进入单词本等核心功能"
                setShowBadge(false)
            }
            val notificationManager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun showNotification(id: String, title: String, body: String, payload: String) {
        createNotificationChannel()

        val intent = Intent(this, MainActivity::class.java).apply {
            action = "com.example.chat.ACTION_VOCABULARY"
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("payload", payload)
        }

        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            NOTIFICATION_ID_BASE,
            intent,
            pendingIntentFlags
        )

        val builder = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setOngoing(true)
            .setAutoCancel(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pendingIntent)

        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID_BASE, builder.build())
        activeNotifications.add(id)
    }

    private fun cancelNotification(id: String) {
        val notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(NOTIFICATION_ID_BASE)
        activeNotifications.remove(id)
    }
}
