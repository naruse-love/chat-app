package love.naruse.chat

import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var methodChannel: MethodChannel? = null

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
            ?: (if (intent.action == "love.naruse.chat.ACTION_VOCABULARY") "/vocabulary" else null)

        if (payload != null) {
            NotificationHelper.launchPayload = payload
            NotificationHelper.activeMethodChannel?.invokeMethod("onNotificationTapped", payload)
        }
    }

    override fun provideFlutterEngine(context: android.content.Context): FlutterEngine? {
        val bgEngine = NotificationHelper.backgroundEngine
        if (bgEngine != null) {
            return bgEngine
        }
        return super.provideFlutterEngine(context)
    }

    override fun shouldDestroyEngineWithHost(): Boolean {
        return NotificationHelper.backgroundEngine == null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
                android.content.pm.PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1001)
            }
        }

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NotificationHelper.CHANNEL_NAME)
        methodChannel = channel
        NotificationHelper.activeMethodChannel = channel
        NotificationHelper.isDartReady = true
        NotificationHelper.setupMethodChannel(this, channel)
    }

    override fun onDestroy() {
        if (NotificationHelper.activeMethodChannel == methodChannel) {
            if (NotificationHelper.backgroundEngine == null) {
                NotificationHelper.activeMethodChannel = null
                NotificationHelper.isDartReady = false
            }
        }
        super.onDestroy()
    }
}
