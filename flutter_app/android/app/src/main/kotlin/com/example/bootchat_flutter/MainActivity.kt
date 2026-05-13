package com.example.bootchat_flutter

import android.content.Context
import android.media.AudioDeviceInfo
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
    private var outgoingRingtone: Ringtone? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var callAudioFocusHeld = false

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
                "startOutgoingTone" -> {
                    startOutgoingTone()
                    result.success(null)
                }
                "stopOutgoingTone" -> {
                    stopOutgoingTone()
                    result.success(null)
                }
                "activateCallAudio" -> {
                    result.success(
                        activateCallAudio(
                        speakerOn = call.argument<Boolean>("speakerOn") ?: true
                        )
                    )
                }
                "restoreAudioRoute" -> {
                    restoreAudioRoute()
                    result.success(null)
                }
                "getAudioRouteInfo" -> {
                    result.success(getAudioRouteInfo())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startIncomingRingtone() {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        val ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            ?: return

        if (incomingRingtone == null) {
            incomingRingtone = RingtoneManager.getRingtone(applicationContext, ringtoneUri)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            incomingRingtone?.audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            incomingRingtone?.isLooping = true
        }

        audioManager?.mode = AudioManager.MODE_NORMAL
        @Suppress("DEPRECATION")
        audioManager?.isSpeakerphoneOn = true
        volumeControlStream = AudioManager.STREAM_RING

        if (incomingRingtone?.isPlaying != true) {
            incomingRingtone?.play()
        }
    }

    private fun stopIncomingRingtone() {
        incomingRingtone?.stop()
    }

    private fun startOutgoingTone() {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        val toneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            ?: return

        if (outgoingRingtone == null) {
            outgoingRingtone = RingtoneManager.getRingtone(applicationContext, toneUri)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            outgoingRingtone?.audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION_SIGNALLING)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            outgoingRingtone?.isLooping = true
        }

        // Use VOICE_CALL stream so the dial tone is audible even when ring volume is 0
        audioManager?.mode = AudioManager.MODE_IN_COMMUNICATION
        @Suppress("DEPRECATION")
        audioManager?.isSpeakerphoneOn = true
        volumeControlStream = AudioManager.STREAM_VOICE_CALL

        // Ensure volume is audible (set to 70% of max if currently 0)
        val maxVol = audioManager?.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL) ?: 0
        val curVol = audioManager?.getStreamVolume(AudioManager.STREAM_VOICE_CALL) ?: 0
        if (curVol == 0 && maxVol > 0) {
            audioManager?.setStreamVolume(AudioManager.STREAM_VOICE_CALL, maxVol * 7 / 10, 0)
        }

        if (outgoingRingtone?.isPlaying != true) {
            outgoingRingtone?.play()
        }
    }

    private fun stopOutgoingTone() {
        outgoingRingtone?.stop()
    }

    private fun activateCallAudio(speakerOn: Boolean): Map<String, Any> {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            ?: return mapOf(
                "currentRoute" to "speaker",
                "hasBluetooth" to false,
                "hasHeadset" to false,
            )

        if (!callAudioFocusHeld) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build()
                    )
                    .setAcceptsDelayedFocusGain(false)
                    .setOnAudioFocusChangeListener { focusChange ->
                        if (focusChange == AudioManager.AUDIOFOCUS_LOSS ||
                            focusChange == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) {
                            // Re-request focus to maintain call audio
                            audioFocusRequest?.let { audioManager.requestAudioFocus(it) }
                        }
                    }
                    .build()
                audioFocusRequest = focusRequest
                audioManager.requestAudioFocus(focusRequest)
            } else {
                @Suppress("DEPRECATION")
                audioManager.requestAudioFocus(
                    null,
                    AudioManager.STREAM_VOICE_CALL,
                    AudioManager.AUDIOFOCUS_GAIN
                )
            }
            callAudioFocusHeld = true
        }

        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager.availableCommunicationDevices
                .firstOrNull { device ->
                    if (speakerOn) {
                        device.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
                    } else {
                        device.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                            device.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                            device.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                            device.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                            device.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
                    }
                }
                ?.let { device ->
                    audioManager.setCommunicationDevice(device)
                }
        }
        if (speakerOn) {
            audioManager.stopBluetoothSco()
            @Suppress("DEPRECATION")
            audioManager.isBluetoothScoOn = false
        }
        @Suppress("DEPRECATION")
        audioManager.isSpeakerphoneOn = speakerOn
        @Suppress("DEPRECATION")
        audioManager.isMicrophoneMute = false
        volumeControlStream = AudioManager.STREAM_VOICE_CALL
        return getAudioRouteInfo()
    }

    private fun restoreAudioRoute() {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        @Suppress("DEPRECATION")
        audioManager.isSpeakerphoneOn = false
        @Suppress("DEPRECATION")
        audioManager.isMicrophoneMute = false
        audioManager.stopBluetoothSco()
        @Suppress("DEPRECATION")
        audioManager.isBluetoothScoOn = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager.clearCommunicationDevice()
        }
        audioManager.mode = AudioManager.MODE_NORMAL
        volumeControlStream = AudioManager.USE_DEFAULT_STREAM_TYPE

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
            audioFocusRequest = null
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(null)
        }
        callAudioFocusHeld = false
    }

    private fun getAudioRouteInfo(): Map<String, Any> {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            ?: return mapOf(
                "currentRoute" to "speaker",
                "hasBluetooth" to false,
                "hasHeadset" to false,
            )

        val outputs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).toList()
        } else {
            emptyList()
        }

        val hasBluetooth = outputs.any {
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
        } || audioManager.isBluetoothScoOn

        val hasHeadset = outputs.any {
            it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                it.type == AudioDeviceInfo.TYPE_USB_HEADSET
        } || audioManager.isWiredHeadsetOn

        val currentRoute = when {
            audioManager.isSpeakerphoneOn -> "speaker"
            hasBluetooth -> "bluetooth"
            hasHeadset -> "headset"
            else -> "earpiece"
        }

        return mapOf(
            "currentRoute" to currentRoute,
            "hasBluetooth" to hasBluetooth,
            "hasHeadset" to hasHeadset,
        )
    }

    override fun onDestroy() {
        stopIncomingRingtone()
        stopOutgoingTone()
        restoreAudioRoute()
        incomingRingtone = null
        outgoingRingtone = null
        super.onDestroy()
    }
}
