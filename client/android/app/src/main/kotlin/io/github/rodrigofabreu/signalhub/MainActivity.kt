package io.github.rodrigofabreu.signalhub

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createEventsChannel()
    }

    // Without a channel of its own, Firebase shows pushes in its fallback
    // channel, "Miscellaneous", at default importance: they make a sound but
    // do not pop up. High importance pops them up. Creating an existing
    // channel changes nothing, so the owner's own settings for it are kept.
    private fun createEventsChannel() {
        // Android 7 has no channels.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            getString(R.string.events_channel_id),
            getString(R.string.events_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        )
        channel.description = getString(R.string.events_channel_description)
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }
}
