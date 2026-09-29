package io.github.rodrigofabreu.signalhub

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build

class SignalHubApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        createEventsChannel()
    }

    // Created with the process, before any push is received or shown, so a
    // push arriving after an update, before the app is opened, never lands
    // in Firebase's fallback channel with the phone's default sound.
    //
    // The channel is high importance, so pushes pop up, but makes no sound
    // and does not vibrate: PushAlertReceiver plays SignalHub's own alert,
    // which Android cannot give a channel at a volume or change once the
    // channel exists. Creating an existing channel changes nothing, so the
    // owner's own settings for it are kept.
    private fun createEventsChannel() {
        // Android 7 has no channels.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            getString(R.string.events_channel_id),
            getString(R.string.events_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        )
        channel.description = getString(R.string.events_channel_description)
        channel.setSound(null, null)
        channel.enableVibration(false)
        val notifications = getSystemService(NotificationManager::class.java)
        notifications.createNotificationChannel(channel)
        // The channel of releases before SignalHub's own alert, which sounded
        // the phone's default: replaced once, its settings not carried over.
        notifications.deleteNotificationChannel(OLD_EVENTS_CHANNEL)
    }

    private companion object {
        const val OLD_EVENTS_CHANNEL = "events"
    }
}
