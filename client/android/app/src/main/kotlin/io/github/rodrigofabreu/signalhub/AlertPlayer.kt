package io.github.rodrigofabreu.signalhub

import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicBoolean

/**
 * What to play for a push, as the app's alert settings give it
 * (AlertSettings.toPlatform in lib/src/alert/alert_settings.dart, and
 * CriticalAlertSettings.toPlatform for a critical push's). The settings
 * themselves are worked out in Dart; this only plays them. [onSilent] and
 * [duringDoNotDisturb], a critical push's only, let it sound when the
 * ringer is on silent or vibrate, and during do-not-disturb.
 */
class Alert(
    val description: String,
    val resource: String?,
    val gain: Float,
    val timings: LongArray,
    val amplitudes: IntArray,
    val fallbackTimings: LongArray,
    val onSilent: Boolean,
    val duringDoNotDisturb: Boolean,
) {
    companion object {
        fun parse(json: String): Alert = parse(JSONObject(json))

        fun parse(alert: JSONObject): Alert {
            return Alert(
                description = "sound=${alert.optString("sound", "none")} " +
                    "volume=${alert.optInt("volume")}% " +
                    "vibration=${alert.optString("vibration")}",
                resource = if (alert.isNull("resource")) null else alert.getString("resource"),
                gain = alert.getDouble("gain").toFloat().coerceIn(0f, 1f),
                timings = longs(alert.getJSONArray("timings")),
                amplitudes = IntArray(alert.getJSONArray("amplitudes").length()) {
                    alert.getJSONArray("amplitudes").getInt(it)
                },
                fallbackTimings = longs(alert.getJSONArray("fallbackTimings")),
                onSilent = alert.optBoolean("onSilent", false),
                duringDoNotDisturb = alert.optBoolean("duringDoNotDisturb", false),
            )
        }

        private fun longs(array: JSONArray) = LongArray(array.length()) { array.getLong(it) }
    }
}

/**
 * Stores the alerts on the device and plays them: the sound on the
 * notification stream, so the phone's notification volume scales it, and
 * the vibration as a notification's, so the phone's vibration settings
 * apply. The general alert never plays through do-not-disturb, and follows
 * the ringer: nothing on silent, only the vibration on vibrate.
 *
 * A critical push's alert may sound on silent or vibrate ([Alert.onSilent])
 * and during do-not-disturb ([Alert.duringDoNotDisturb], only while the
 * owner gives the app Do Not Disturb access). When it does, it plays as an
 * alarm, on the alarm stream at the phone's alarm volume, which neither the
 * ringer nor do-not-disturb's default of letting alarms through mutes.
 */
object AlertPlayer {
    const val TAG = "SignalHubAlert"
    private const val PREFERENCES = "signalhub_alert"
    private const val KEY = "alert"
    private const val LONGEST_SOUND_MS = 5000L

    /** The push data's generic severity whose alert is its own. */
    private const val CRITICAL = "CRITICAL"

    private fun attributes(usage: Int): AudioAttributes = AudioAttributes.Builder()
        .setUsage(usage)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()

    /** What [save] stored, or null before the app saved any settings. */
    fun load(context: Context): String? =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).getString(KEY, null)

    fun save(context: Context, json: String) {
        val alerts = JSONObject(json)
        Alert.parse(alerts)
        alerts.optJSONObject("criticalAlert")?.let { Alert.parse(it) }
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit().putString(KEY, json).apply()
    }

    /**
     * What a push of [severity] plays, and what to log it as: a critical
     * push's alert (platformAlerts in alert_settings.dart), or the general
     * alert for any other severity, one this app does not know, or none;
     * the saved alerts, or the defaults the app would save.
     */
    fun forPush(context: Context, severity: String?): Pair<String, Alert> {
        val alerts = JSONObject(
            load(context) ?: context.resources.openRawResource(R.raw.signalhub_alert_defaults)
                .bufferedReader().use { it.readText() },
        )
        // Saved by a release without critical alerts: until the app is
        // opened and saves them, a critical push plays the general alert.
        val critical = if (severity == CRITICAL) alerts.optJSONObject("criticalAlert") else null
        return if (critical != null) {
            "Critical alert" to Alert.parse(critical)
        } else {
            "Alert" to Alert.parse(alerts)
        }
    }

    /**
     * Plays [alert] unless the phone keeps it quiet, and logs it as [kind]
     * (the device review reads the log). Returns whether any of it plays;
     * [done] runs once the sound has ended, or at once without one.
     */
    fun play(context: Context, alert: Alert, kind: String, done: () -> Unit = {}): Boolean {
        val finished = AtomicBoolean(false)
        val finish = { if (finished.compareAndSet(false, true)) done() }
        val notifications = context.getSystemService(NotificationManager::class.java)
        val filter = notifications.currentInterruptionFilter
        val doNotDisturb = filter != NotificationManager.INTERRUPTION_FILTER_ALL &&
            filter != NotificationManager.INTERRUPTION_FILTER_UNKNOWN
        val ringer = context.getSystemService(AudioManager::class.java).ringerMode
        val normal = ringer == AudioManager.RINGER_MODE_NORMAL
        val quiet = when {
            doNotDisturb && !alert.duringDoNotDisturb -> "do not disturb"
            doNotDisturb && !notifications.isNotificationPolicyAccessGranted ->
                "do not disturb, no Do Not Disturb access"
            // Total silence mutes alarms too.
            filter == NotificationManager.INTERRUPTION_FILTER_NONE ->
                "do not disturb, total silence"
            ringer == AudioManager.RINGER_MODE_SILENT && !alert.onSilent -> "silent mode"
            else -> null
        }
        if (quiet != null) {
            Log.i(TAG, "$kind not played ($quiet): ${alert.description}")
            finish()
            return false
        }
        // Past the ringer or do-not-disturb, it plays as an alarm, which
        // they do not mute; otherwise as the notification it is.
        val asAlarm = doNotDisturb || (!normal && alert.onSilent)
        val usage = if (asAlarm) AudioAttributes.USAGE_ALARM else AudioAttributes.USAGE_NOTIFICATION
        val sound = (normal || alert.onSilent) && playSound(context, alert, usage, finish)
        val vibration = vibrate(context, alert, asAlarm)
        if (!sound) finish()
        Log.i(
            TAG,
            "$kind played (sound ${if (sound) "on" else "off"}, " +
                "vibration ${if (vibration) "on" else "off"}" +
                "${if (asAlarm) ", as an alarm" else ""}): ${alert.description}",
        )
        return sound || vibration
    }

    private fun playSound(context: Context, alert: Alert, usage: Int, finish: () -> Unit): Boolean {
        val resource = alert.resource ?: return false
        // Sounds are named by the app's settings; keep.xml keeps them.
        @Suppress("DiscouragedApi")
        val id = context.resources.getIdentifier(resource, "raw", context.packageName)
        if (id == 0) return false
        val player = MediaPlayer()
        val released = AtomicBoolean(false)
        val release = {
            if (released.compareAndSet(false, true)) player.release()
            finish()
        }
        return try {
            player.setAudioAttributes(attributes(usage))
            context.resources.openRawResourceFd(id).use {
                player.setDataSource(it.fileDescriptor, it.startOffset, it.length)
            }
            player.setVolume(alert.gain, alert.gain)
            player.setOnCompletionListener { release() }
            player.setOnErrorListener { _, _, _ ->
                release()
                true
            }
            player.prepare()
            player.start()
            Handler(Looper.getMainLooper()).postDelayed({ release() }, LONGEST_SOUND_MS)
            true
        } catch (e: Exception) {
            Log.w(TAG, "Alert sound not played: ${e.javaClass.simpleName}")
            release()
            false
        }
    }

    private fun vibrate(context: Context, alert: Alert, asAlarm: Boolean): Boolean {
        if (alert.timings.isEmpty()) return false
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Vibrator::class.java)
        }
        if (!vibrator.hasVibrator()) return false
        val attributes = attributes(
            if (asAlarm) AudioAttributes.USAGE_ALARM else AudioAttributes.USAGE_NOTIFICATION,
        )
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            vibrator.vibrate(alert.fallbackTimings, -1, attributes)
            return true
        }
        // Without amplitude control, the steps are the buzzes' lengths.
        val effect = if (vibrator.hasAmplitudeControl()) {
            VibrationEffect.createWaveform(alert.timings, alert.amplitudes, -1)
        } else {
            VibrationEffect.createWaveform(alert.fallbackTimings, -1)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            vibrator.vibrate(
                effect,
                VibrationAttributes.createForUsage(
                    if (asAlarm) VibrationAttributes.USAGE_ALARM else VibrationAttributes.USAGE_NOTIFICATION,
                ),
            )
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(effect, attributes)
        }
        return true
    }
}
