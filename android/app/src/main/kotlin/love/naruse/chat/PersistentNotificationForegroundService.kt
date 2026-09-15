package love.naruse.chat

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder

class PersistentNotificationForegroundService : Service() {
    companion object {
        const val ACTION_START = "love.naruse.chat.START_FOREGROUND_NOTIFICATION"
        const val ACTION_STOP = "love.naruse.chat.STOP_FOREGROUND_NOTIFICATION"
        const val EXTRA_ID = "id"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_PAYLOAD = "payload"

        fun startService(
            context: Context,
            id: String,
            title: String,
            body: String,
            payload: String?
        ) {
            val intent = Intent(context, PersistentNotificationForegroundService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_ID, id)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_BODY, body)
                putExtra(EXTRA_PAYLOAD, payload)
            }
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stopService(context: Context, id: String) {
            val intent = Intent(context, PersistentNotificationForegroundService::class.java).apply {
                action = ACTION_STOP
                putExtra(EXTRA_ID, id)
            }
            context.startService(intent)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) return START_STICKY

        when (intent.action) {
            ACTION_START -> {
                val id = intent.getStringExtra(EXTRA_ID) ?: "chat_persistent_vocab"
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "📚 日语生词快捷查询"
                val body = intent.getStringExtra(EXTRA_BODY) ?: "点击「🔍 输入单词」直接在通知栏查词"
                val payload = intent.getStringExtra(EXTRA_PAYLOAD) ?: "/vocabulary"

                val notification = NotificationHelper.buildInitialNotification(
                    this, id, title, body, payload
                )
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                    startForeground(
                        NotificationHelper.getNotificationIntId(id),
                        notification,
                        android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                    )
                } else {
                    startForeground(NotificationHelper.getNotificationIntId(id), notification)
                }
                NotificationHelper.activeNotifications.add(id)
            }
            ACTION_STOP -> {
                val id = intent.getStringExtra(EXTRA_ID) ?: "chat_persistent_vocab"
                NotificationHelper.cancelNotification(this, id)
                NotificationHelper.destroyBackgroundEngine()
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
                stopSelf()
            }
        }

        return START_STICKY
    }
}
