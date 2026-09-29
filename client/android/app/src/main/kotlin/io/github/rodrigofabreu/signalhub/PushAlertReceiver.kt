package io.github.rodrigofabreu.signalhub

import android.app.ActivityManager
import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log

/**
 * Plays SignalHub's alert for a push the system shows: the events channel
 * is silent, so this is the push's sound and vibration, a critical push's
 * own or the general one. It receives every
 * FCM message, alongside Firebase's own receivers, which show the
 * notification.
 */
class PushAlertReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val extras = intent.extras ?: return
        if (!isShownNotification(extras)) return
        val app = context.applicationContext
        // In the foreground Firebase shows nothing: the app's own notice.
        if (inForeground(app)) {
            Log.i(AlertPlayer.TAG, "Alert not played (the app is in the foreground)")
            return
        }
        val muted = mutedByOwner(app)
        if (muted != null) {
            Log.i(AlertPlayer.TAG, "Alert not played ($muted)")
            return
        }
        // By the push data's generic severity alone, never its producer,
        // category or text.
        val (kind, alert) = AlertPlayer.forPush(app, extras.getString("severity"))
        val pending = goAsync()
        AlertPlayer.play(app, alert, kind) { pending.finish() }
    }

    /**
     * Whether Firebase shows this message as a notification: a message
     * with a notification part, which every SignalHub push has, and not an
     * FCM housekeeping message.
     */
    private fun isShownNotification(extras: Bundle): Boolean {
        val type = extras.getString("message_type")
        if (type != null && type != "gcm") return false
        return extras.keySet().any { it.startsWith("gcm.n.") || it.startsWith("gcm.notification.") }
    }

    /** As Firebase decides it: the app in front and the phone unlocked. */
    private fun inForeground(context: Context): Boolean {
        if (context.getSystemService(KeyguardManager::class.java).isKeyguardLocked) return false
        val process = ActivityManager.RunningAppProcessInfo()
        ActivityManager.getMyMemoryState(process)
        return process.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
    }

    /**
     * Why the owner's notification settings for SignalHub keep its pushes
     * quiet, or null: notifications off, or the channel made silent or off.
     */
    private fun mutedByOwner(context: Context): String? {
        val notifications = context.getSystemService(NotificationManager::class.java)
        if (!notifications.areNotificationsEnabled()) return "notifications are off"
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val channel = notifications.getNotificationChannel(
            context.getString(R.string.events_channel_id),
        ) ?: return null
        return if (channel.importance < NotificationManager.IMPORTANCE_DEFAULT) {
            "the channel is silent"
        } else {
            null
        }
    }
}
