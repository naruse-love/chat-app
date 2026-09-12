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

        val pendingResult = goAsync()
        NotificationHelper.handleInlineQuery(context, id, query) {
            try {
                pendingResult.finish()
            } catch (_: Exception) {}
        }
    }
}
