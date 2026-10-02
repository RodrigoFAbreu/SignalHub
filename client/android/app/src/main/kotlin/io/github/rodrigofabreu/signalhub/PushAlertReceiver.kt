package io.github.rodrigofabreu.signalhub

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log

/**
 * Plays SignalHub's alert for every push: the events channel is silent, so
 * this is the push's sound and vibration, a critical push's own or the
 * general one. It receives every FCM message, alongside Firebase's own
 * receivers, which show the notification in the background and hand the
 * push to the app in the foreground. Playing it here, and nowhere else,
 * whether the app is open or not, plays it once per push.
 */
class PushAlertReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val extras = intent.extras ?: return
        if (!isNotification(extras)) return
        val app = context.applicationContext
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
     * Whether this message is a notification: a message with a
     * notification part, which every SignalHub push has, and not an FCM
     * housekeeping message.
     */
    private fun isNotification(extras: Bundle): Boolean {
        val type = extras.getString("message_type")
        if (type != null && type != "gcm") return false
        return extras.keySet().any { it.startsWith("gcm.n.") || it.startsWith("gcm.notification.") }
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
