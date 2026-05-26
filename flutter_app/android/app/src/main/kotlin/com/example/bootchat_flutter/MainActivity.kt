package com.example.bootchat_flutter

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Timer
import java.util.TimerTask

class MainActivity : FlutterActivity() {
    private var incomingRingtone: Ringtone? = null
    private var ringtoneStopped = false
    private var outgoingToneGenerator: ToneGenerator? = null
    private var outgoingToneTimer: Timer? = null

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
                "activateBluetooth" -> {
                    activateBluetooth()
                    result.success(null)
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
        // Agar stop avval chaqirilgan bo'lsa (race condition) — boshlamaymiz
        if (ringtoneStopped) {
            ringtoneStopped = false
            return
        }
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
        ringtoneStopped = true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            incomingRingtone?.isLooping = false
        }
        incomingRingtone?.stop()
        incomingRingtone = null
    }

    // Plays the standard ringback tone ("tuu...tuu...") that callers hear
    // while waiting for the other side to answer.
    private fun startOutgoingTone() {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager

        audioManager?.mode = AudioManager.MODE_IN_COMMUNICATION
        @Suppress("DEPRECATION")
        audioManager?.isSpeakerphoneOn = true
        volumeControlStream = AudioManager.STREAM_VOICE_CALL

        val maxVol = audioManager?.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL) ?: 0
        val curVol = audioManager?.getStreamVolume(AudioManager.STREAM_VOICE_CALL) ?: 0
        if (curVol == 0 && maxVol > 0) {
            audioManager?.setStreamVolume(AudioManager.STREAM_VOICE_CALL, maxVol * 7 / 10, 0)
        }

        stopOutgoingTone()

        try {
            outgoingToneGenerator = ToneGenerator(AudioManager.STREAM_VOICE_CALL, 100)
            outgoingToneTimer = Timer()
            // Play 1-second ringback beep, pause 3 seconds, repeat
            outgoingToneTimer?.scheduleAtFixedRate(object : TimerTask() {
                override fun run() {
                    outgoingToneGenerator?.startTone(ToneGenerator.TONE_SUP_RINGTONE, 1000)
                }
            }, 0L, 4000L)
        } catch (e: Exception) {
            // ToneGenerator may fail on some devices; fall through silently
        }
    }

    private fun stopOutgoingTone() {
        outgoingToneTimer?.cancel()
        outgoingToneTimer = null
        outgoingToneGenerator?.release()
        outgoingToneGenerator = null
    }

    private fun activateCallAudio(speakerOn: Boolean): Map<String, Any> {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            ?: return mapOf(
                "currentRoute" to "speaker",
                "hasBluetooth" to false,
                "hasHeadset" to false,
            )

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

    private fun activateBluetooth() {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        @Suppress("DEPRECATION")
        audioManager.isSpeakerphoneOn = false
        audioManager.startBluetoothSco()
        @Suppress("DEPRECATION")
        audioManager.isBluetoothScoOn = true
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
        super.onDestroy()
    }
}
