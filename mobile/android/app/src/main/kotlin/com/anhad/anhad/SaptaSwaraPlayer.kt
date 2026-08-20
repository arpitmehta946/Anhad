package com.anhad.anhad

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaPlayer

/**
 * Plays the sapta swara arrival tones (docs/FRONTEND_GUIDELINES.md §12)
 * through the phone's built-in speaker specifically — the mirror image of
 * [JapaBellPlayer], which deliberately goes the other way (headphone/
 * Bluetooth only, never speaker). This is a once-per-open, first-thing-
 * heard moment; it shouldn't silently disappear into a paired Bluetooth
 * device that happens to be connected but not actually being listened to
 * (a car system, earbuds left in a bag) the way it was before this existed
 * — just_audio has no way to steer around that from the Dart side, which
 * is why this needs to be native.
 *
 * A plain [MediaPlayer] per note rather than a shared pool: the seven
 * notes deliberately overlap (each one rings into the next), so pooling
 * into a single player would cut one off to start the next.
 */
object SaptaSwaraPlayer {
    fun play(context: Context, path: String) {
        val appContext = context.applicationContext
        val player = MediaPlayer()
        try {
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build(),
            )
            builtInSpeaker(appContext)?.let { player.preferredDevice = it }
            player.setDataSource(path)
            player.setOnCompletionListener { it.release() }
            player.setOnErrorListener { mp, _, _ -> mp.release(); true }
            player.prepare()
            player.start()
        } catch (e: Exception) {
            player.release()
        }
    }

    private fun builtInSpeaker(context: Context): AudioDeviceInfo? {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
    }
}
