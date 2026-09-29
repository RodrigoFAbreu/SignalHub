package io.github.rodrigofabreu.signalhub

import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONException

class MainActivity : FlutterActivity() {
    // The alert settings screen (lib/src/alert/alert_platform.dart).
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
    }

    // Opening the app, or a notification, which opens it, ends a long alert.
    override fun onResume() {
        super.onResume()
        AlertPlayer.stopVibration(this)
    }

    private companion object {
        const val ALERT_CHANNEL = "io.github.rodrigofabreu.signalhub/alert"
    }
}
