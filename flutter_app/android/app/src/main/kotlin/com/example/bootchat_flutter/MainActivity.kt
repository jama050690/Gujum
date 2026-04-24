package com.example.bootchat_flutter

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var incomingRingtone: Ringtone? = null
    private var audioFocusRequest: AudioFocusRequest? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "bootchat/call_audio"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startIncomingRingtone" -> {
                    startIncomingRingtone()
                    result.success(null)
                }
                "stopIncomingRingtone" -> {
                    stopIncomingRingtone()
                    result.success(null)
                }
                "activateCallAudio" -> {
                    activateCallAudio(
                        speakerOn = call.argument<Boolean>("speakerOn") ?: true
                    )
                    result.success(null)
                }
                "restoreAudioRoute" -> {
                    restoreAudioRoute()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startIncomingRingtone() {
        val ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            ?: return

        if (incomingRingtone == null) {
            incomingRingtone = RingtoneManager.getRingtone(applicationContext, ringtoneUri)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            incomingRingtone?.isLooping = true
        }

        if (incomingRingtone?.isPlaying != true) {
            incomingRingtone?.play()
        }
    }

    private fun stopIncomingRingtone() {
        incomingRingtone?.stop()
    }

    private fun activateCallAudio(speakerOn: Boolean) {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                .setAcceptsDelayedFocusGain(false)
                .setOnAudioFocusChangeListener { }
                .build()
            audioFocusRequest = focusRequest
            audioManager.requestAudioFocus(focusRequest)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                null,
                AudioManager.STREAM_VOICE_CALL,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
            )
        }

        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        @Suppress("DEPRECATION")
        audioManager.isSpeakerphoneOn = speakerOn
        @Suppress("DEPRECATION")
        audioManager.isMicrophoneMute = false
    }

    private fun restoreAudioRoute() {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        @Suppress("DEPRECATION")
        audioManager.isSpeakerphoneOn = false
        @Suppress("DEPRECATION")
        audioManager.isMicrophoneMute = false
        audioManager.mode = AudioManager.MODE_NORMAL

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
            audioFocusRequest = null
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(null)
        }
    }

    override fun onDestroy() {
        stopIncomingRingtone()
        restoreAudioRoute()
        incomingRingtone = null
        super.onDestroy()
    }
}
