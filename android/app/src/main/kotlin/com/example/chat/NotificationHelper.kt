package com.example.chat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.RemoteInput
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

object NotificationHelper {
    const val CHANNEL_NAME = "com.example.chat/persistent_notification"
    const val NOTIFICATION_CHANNEL_ID = "chat_persistent_shortcuts"
    const val NOTIFICATION_CHANNEL_NAME = "常驻查词入口"
    const val NOTIFICATION_ID_BASE = 9988
    const val KEY_TEXT_REPLY = "key_inline_vocab_query"
    const val ACTION_INLINE_SEARCH = "com.example.chat.ACTION_INLINE_SEARCH"

    var activeMethodChannel: MethodChannel? = null
    var backgroundEngine: FlutterEngine? = null
    var launchPayload: String? = null
    val activeNotifications = mutableSetOf<String>()

    fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                NOTIFICATION_CHANNEL_NAME,
                importance
            ).apply {
                description = "日语生词快捷查询常驻通知，支持直接在通知栏输入单词与即时展示双语释义"
                setShowBadge(false)
            }
            val notificationManager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    fun getNotificationIntId(id: String): Int {
        return NOTIFICATION_ID_BASE + (id.hashCode() and 0x0FFF)
    }

    private fun createRemoteInputAction(context: Context, id: String): NotificationCompat.Action {
        val remoteInput = RemoteInput.Builder(KEY_TEXT_REPLY)
            .setLabel("输入日语单词...")
            .build()

        val replyIntent = Intent(context, NotificationActionReceiver::class.java).apply {
            action = ACTION_INLINE_SEARCH
            putExtra("id", id)
        }

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val replyPendingIntent = PendingIntent.getBroadcast(
            context,
            getNotificationIntId(id) + 1,
            replyIntent,
            flags
        )

        return NotificationCompat.Action.Builder(
            android.R.drawable.ic_menu_search,
            "🔍 输入单词",
            replyPendingIntent
        )
        .addRemoteInput(remoteInput)
        .setAllowGeneratedReplies(true)
        .build()
    }

    private fun createContentIntent(context: Context, id: String, payload: String?): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = "com.example.chat.ACTION_VOCABULARY"
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("payload", payload ?: "/vocabulary")
        }

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        return PendingIntent.getActivity(
            context,
            getNotificationIntId(id),
            intent,
            flags
        )
    }

    fun buildInitialNotification(
        context: Context,
        id: String,
        title: String,
        body: String,
        payload: String?
    ): Notification {
        createNotificationChannel(context)
        val contentPendingIntent = createContentIntent(context, id, payload)
        val replyAction = createRemoteInputAction(context, id)

        return NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setOngoing(true)
            .setAutoCancel(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(contentPendingIntent)
            .addAction(replyAction)
            .build()
    }

    fun buildSearchingNotification(
        context: Context,
        id: String,
        query: String
    ): Notification {
        createNotificationChannel(context)
        val contentPendingIntent = createContentIntent(context, id, "/vocabulary")
        val replyAction = createRemoteInputAction(context, id)

        return NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("🔍 正在查询「$query」...")
            .setContentText("正在获取释义与翻译，请稍候...")
            .setOngoing(true)
            .setAutoCancel(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(contentPendingIntent)
            .addAction(replyAction)
            .build()
    }

    fun buildSearchResultNotification(
        context: Context,
        id: String,
        word: String,
        reading: String?,
        definitionJa: String?,
        definitionSc: String?,
        partOfSpeech: String?,
        isLoading: Boolean,
        error: String?
    ): Notification {
        createNotificationChannel(context)
        val contentPendingIntent = createContentIntent(context, id, "/vocabulary")
        val replyAction = createRemoteInputAction(context, id)

        if (isLoading) {
            return buildSearchingNotification(context, id, word)
        }

        if (error != null) {
            val bigStyle = NotificationCompat.BigTextStyle()
                .setBigContentTitle("⚠️ 未找到「$word」的释义")
                .bigText("$error\n提示：可点击本通知打开生词本进行深入查询或使用 AI 推测。")

            return NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("⚠️ 未找到「$word」的释义")
                .setContentText(error)
                .setStyle(bigStyle)
                .setOngoing(true)
                .setAutoCancel(false)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setContentIntent(contentPendingIntent)
                .addAction(replyAction)
                .build()
        }

        val title = if (!reading.isNullOrEmpty() && reading != word) {
            "📖 $word【$reading】"
        } else {
            "📖 $word"
        }

        val shortBody = when {
            !definitionSc.isNullOrEmpty() -> definitionSc
            !definitionJa.isNullOrEmpty() -> definitionJa
            else -> "已收录至生词本"
        }

        val bigTextBuilder = StringBuilder()
        if (!reading.isNullOrEmpty()) {
            bigTextBuilder.append("【读音】").append(reading).append("\n")
        }
        if (!partOfSpeech.isNullOrEmpty()) {
            bigTextBuilder.append("【词性】").append(partOfSpeech).append("\n")
        }
        if (!definitionSc.isNullOrEmpty()) {
            bigTextBuilder.append("【中文】").append(definitionSc).append("\n")
        }
        if (!definitionJa.isNullOrEmpty()) {
            bigTextBuilder.append("【日文】").append(definitionJa)
        }

        val bigStyle = NotificationCompat.BigTextStyle()
            .setBigContentTitle(title)
            .setSummaryText(if (!partOfSpeech.isNullOrEmpty()) partOfSpeech else "生词释义")
            .bigText(bigTextBuilder.toString().trim())

        return NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(shortBody)
            .setStyle(bigStyle)
            .setOngoing(true)
            .setAutoCancel(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(contentPendingIntent)
            .addAction(replyAction)
            .build()
    }

    fun showNotification(
        context: Context,
        id: String,
        title: String,
        body: String,
        payload: String?
    ) {
        val notification = buildInitialNotification(context, id, title, body, payload)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(getNotificationIntId(id), notification)
        activeNotifications.add(id)
    }

    fun showSearchingNotification(
        context: Context,
        id: String,
        query: String
    ) {
        val notification = buildSearchingNotification(context, id, query)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(getNotificationIntId(id), notification)
        activeNotifications.add(id)
    }

    fun updateNotificationWithResult(
        context: Context,
        id: String,
        word: String,
        reading: String?,
        definitionJa: String?,
        definitionSc: String?,
        partOfSpeech: String?,
        isLoading: Boolean,
        error: String?
    ) {
        val notification = buildSearchResultNotification(
            context, id, word, reading, definitionJa, definitionSc, partOfSpeech, isLoading, error
        )
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(getNotificationIntId(id), notification)
        activeNotifications.add(id)
    }

    fun cancelNotification(context: Context, id: String) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(getNotificationIntId(id))
        activeNotifications.remove(id)
    }

    fun setupMethodChannel(context: Context, channel: MethodChannel) {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "showPersistentNotification" -> {
                    val id = call.argument<String>("id") ?: "chat_persistent_vocab"
                    val title = call.argument<String>("title") ?: "📚 日语生词快捷查询"
                    val body = call.argument<String>("body") ?: "点击「🔍 输入单词」直接在通知栏查词"
                    val payload = call.argument<String>("payload") ?: "/vocabulary"

                    try {
                        PersistentNotificationForegroundService.startService(
                            context, id, title, body, payload
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            showNotification(context, id, title, body, payload)
                            result.success(true)
                        } catch (ex: Exception) {
                            result.error("NOTIFICATION_ERROR", ex.message, null)
                        }
                    }
                }
                "cancelPersistentNotification" -> {
                    val id = call.argument<String>("id") ?: "chat_persistent_vocab"
                    try {
                        PersistentNotificationForegroundService.stopService(context, id)
                        cancelNotification(context, id)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("NOTIFICATION_ERROR", e.message, null)
                    }
                }
                "updateSearchResultNotification" -> {
                    val id = call.argument<String>("id") ?: "chat_persistent_vocab"
                    val word = call.argument<String>("word") ?: ""
                    val reading = call.argument<String>("reading")
                    val definitionJa = call.argument<String>("definitionJa")
                    val definitionSc = call.argument<String>("definitionSc")
                    val partOfSpeech = call.argument<String>("partOfSpeech")
                    val isLoading = call.argument<Boolean>("isLoading") ?: false
                    val error = call.argument<String>("error")

                    try {
                        updateNotificationWithResult(
                            context,
                            id,
                            word,
                            reading,
                            definitionJa,
                            definitionSc,
                            partOfSpeech,
                            isLoading,
                            error
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("NOTIFICATION_ERROR", e.message, null)
                    }
                }
                "isNotificationActive" -> {
                    val id = call.argument<String>("id") ?: "chat_persistent_vocab"
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

    fun ensureBackgroundEngine(context: Context, onReady: (MethodChannel) -> Unit) {
        val active = activeMethodChannel
        if (active != null) {
            onReady(active)
            return
        }

        try {
            if (backgroundEngine == null) {
                val engine = FlutterEngine(context.applicationContext)
                engine.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint.createDefault()
                )
                val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)
                setupMethodChannel(context.applicationContext, channel)
                backgroundEngine = engine
                activeMethodChannel = channel
            }
            activeMethodChannel?.let(onReady)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
