package io.github.rodrigofabreu.signalhub

import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONException

class MainActivity : FlutterActivity() {
    // The sign-in link the app was started with, until the app asks for it
    // (lib/src/connection/incoming_links.dart).
    private var launchLink: String? = null
    private var linksChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        launchLink = signInLink(intent)
    }

    // A link opened while the app is running (the activity is single top).
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        signInLink(intent)?.let { linksChannel?.invokeMethod("link", it) }
    }

    // Only a sign-in link from the page's Open the app button, never one the
    // phone replays when the app is brought back from the recent apps.
    private fun signInLink(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return null
        val data = intent.data ?: return null
        return if (data.scheme == "signalhub" && data.host == "signin") data.toString() else null
    }

    // The alert settings screen (lib/src/alert/alert_platform.dart).
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        configureShareChannel(flutterEngine)
        configureNotificationsChannel(flutterEngine)
        linksChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LINKS_CHANNEL)
            .also { channel ->
                channel.setMethodCallHandler { call, result ->
                    if (call.method == "initialLink") {
                        result.success(launchLink)
                        launchLink = null
                    } else {
                        result.notImplemented()
                    }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALERT_CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "load" -> result.success(AlertPlayer.load(this))
                        "save" -> {
                            AlertPlayer.save(this, call.arguments as String)
                            result.success(null)
                        }
                        "preview" -> result.success(
                            AlertPlayer.play(this, Alert.parse(call.arguments as String), "Preview"),
                        )
                        "doNotDisturbAccess" -> result.success(
                            getSystemService(NotificationManager::class.java)
                                .isNotificationPolicyAccessGranted,
                        )
                        "openDoNotDisturbAccess" -> {
                            startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: JSONException) {
                    result.error("invalid", e.message, null)
                } catch (e: ActivityNotFoundException) {
                    result.error("unavailable", e.message, null)
                }
            }
        // The setup screen's way to the camera permission (lib/src/ui/app_settings.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openAppSettings" -> try {
                        startActivity(
                            Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.parse("package:$packageName"),
                            ),
                        )
                        result.success(null)
                    } catch (e: ActivityNotFoundException) {
                        result.error("unavailable", e.message, null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // The share sheet of a key shown once (lib/src/ui/text_sharer.dart).
    private fun configureShareChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "text") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val send = Intent(Intent.ACTION_SEND)
                    .setType("text/plain")
                    .putExtra(Intent.EXTRA_TEXT, call.arguments as String)
                try {
                    startActivity(Intent.createChooser(send, null))
                    result.success(true)
                } catch (e: ActivityNotFoundException) {
                    result.success(false)
                }
            }
    }

    // An answered question's notification (lib/src/push/event_notifications.dart).
    private fun configureNotificationsChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATIONS_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "remove") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                PushAlertReceiver.removeEventNotification(this, call.arguments as String)
                result.success(null)
            }
    }

    // Opening the app, or a notification, which opens it, ends a long alert.
    override fun onResume() {
        super.onResume()
        AlertPlayer.stopVibration(this)
    }

    private companion object {
        const val ALERT_CHANNEL = "io.github.rodrigofabreu.signalhub/alert"
        const val SHARE_CHANNEL = "io.github.rodrigofabreu.signalhub/share"
        const val LINKS_CHANNEL = "io.github.rodrigofabreu.signalhub/links"
        const val APP_CHANNEL = "io.github.rodrigofabreu.signalhub/app"
        const val NOTIFICATIONS_CHANNEL = "io.github.rodrigofabreu.signalhub/notifications"
    }
}
