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
 * (AlertSettings.toPlatform in lib/src/alert/alert_settings.dart). The
 * settings themselves are worked out in Dart; this only plays them.
 */
class Alert(
    val description: String,
    val resource: String?,
    val gain: Float,
    val timings: LongArray,
    val amplitudes: IntArray,
    val fallbackTimings: LongArray,
) {
    companion object {
        fun parse(json: String): Alert {
            val alert = JSONObject(json)
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
            )
        }

        private fun longs(array: JSONArray) = LongArray(array.length()) { array.getLong(it) }
    }
}

/**
 * Stores the alert on the device and plays it: the sound on the
 * notification stream, so the phone's notification volume scales it, and
 * the vibration as a notification's, so the phone's vibration settings
 * apply. It never plays through do-not-disturb, and follows the ringer:
 * nothing on silent, only the vibration on vibrate.
 */
object AlertPlayer {
    const val TAG = "SignalHubAlert"
    private const val PREFERENCES = "signalhub_alert"
    private const val KEY = "alert"
    private const val LONGEST_SOUND_MS = 5000L

    private val attributes: AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()

    /** What [save] stored, or null before the app saved any settings. */
    fun load(context: Context): String? =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).getString(KEY, null)

    fun save(context: Context, json: String) {
        Alert.parse(json)
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit().putString(KEY, json).apply()
    }

    /** The saved alert, or the defaults the app would save. */
    fun stored(context: Context): Alert = Alert.parse(
        load(context) ?: context.resources.openRawResource(R.raw.signalhub_alert_defaults)
            .bufferedReader().use { it.readText() },
    )

    /**
     * Plays [alert] unless the phone keeps it quiet, and logs it as [kind]
     * (the device review reads the log). Returns whether any of it plays;
     * [done] runs once the sound has ended, or at once without one.
     */
    fun play(context: Context, alert: Alert, kind: String, done: () -> Unit = {}): Boolean {
        val finished = AtomicBoolean(false)
        val finish = { if (finished.compareAndSet(false, true)) done() }
        val quiet = quietReason(context)
        if (quiet != null) {
            Log.i(TAG, "$kind not played ($quiet): ${alert.description}")
            finish()
            return false
        }
        val ringer = context.getSystemService(AudioManager::class.java).ringerMode
        val sound = ringer == AudioManager.RINGER_MODE_NORMAL && playSound(context, alert, finish)
        val vibration = vibrate(context, alert)
        if (!sound) finish()
        Log.i(
            TAG,
            "$kind played (sound ${if (sound) "on" else "off"}, " +
                "vibration ${if (vibration) "on" else "off"}): ${alert.description}",
        )
        return sound || vibration
    }

    /** Why the phone keeps every alert quiet now, or null. */
    private fun quietReason(context: Context): String? {
        val notifications = context.getSystemService(NotificationManager::class.java)
        val filter = notifications.currentInterruptionFilter
        if (filter != NotificationManager.INTERRUPTION_FILTER_ALL &&
            filter != NotificationManager.INTERRUPTION_FILTER_UNKNOWN
        ) {
            return "do not disturb"
        }
        val ringer = context.getSystemService(AudioManager::class.java).ringerMode
        return if (ringer == AudioManager.RINGER_MODE_SILENT) "silent mode" else null
    }

    private fun playSound(context: Context, alert: Alert, finish: () -> Unit): Boolean {
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
            player.setAudioAttributes(attributes)
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

    private fun vibrate(context: Context, alert: Alert): Boolean {
        if (alert.timings.isEmpty()) return false
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Vibrator::class.java)
        }
        if (!vibrator.hasVibrator()) return false
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
                VibrationAttributes.createForUsage(VibrationAttributes.USAGE_NOTIFICATION),
            )
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(effect, attributes)
        }
        return true
    }
}
