package com.example.chat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.RemoteInput

class NotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != NotificationHelper.ACTION_INLINE_SEARCH) return

        val id = intent.getStringExtra("id") ?: "chat_persistent_vocab"
        val remoteInputResults = RemoteInput.getResultsFromIntent(intent)
        val query = remoteInputResults?.getCharSequence(NotificationHelper.KEY_TEXT_REPLY)?.toString()?.trim()

        if (query.isNullOrEmpty()) return

        // 1. 立即更新通知栏显示正在查询状态，提供即时视觉反馈并收起系统行内输入框
        NotificationHelper.showSearchingNotification(context, id, query)

        // 2. 将输入事件传递给 Flutter 引擎（若引擎休眠则按需拉起）
        NotificationHelper.ensureBackgroundEngine(context) { channel ->
            channel.invokeMethod("onInlineQuerySubmitted", mapOf(
                "id" to id,
                "query" to query
            ))
        }
    }
}
