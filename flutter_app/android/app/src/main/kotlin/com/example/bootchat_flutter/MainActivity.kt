package com.example.bootchat_flutter

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
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
                "requestBatteryExemption" -> {
                    val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
                    val pkg = packageName
                    if (pm != null && !pm.isIgnoringBatteryOptimizations(pkg)) {
                        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                        intent.data = Uri.parse("package:$pkg")
                        startActivity(intent)
                    }
                    result.success(null)
                }
                "startOnlineService" -> {
                    val intent = Intent(this, OnlineService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "stopOnlineService" -> {
                    stopService(Intent(this, OnlineService::class.java))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startIncomingRingtone() {
        ringtoneStopped = false
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
        // Audio mode'ni tozalaymiz — activateCallAudio uni qayta o'rnatadi.
        // MODE_NORMAL → MODE_IN_COMMUNICATION o'tishida shovqin kamaytiradi.
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        @Suppress("DEPRECATION")
        audioManager?.isSpeakerphoneOn = false
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
        try { outgoingToneGenerator?.stopTone() } catch (_: Exception) {}
        try { outgoingToneGenerator?.release() } catch (_: Exception) {}
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
            if (speakerOn) {
                // Bluetooth quloqchin ulangan bo'lsa — uni ustunlik bering
                val btDevice = audioManager.availableCommunicationDevices.firstOrNull {
                    it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                    it.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                    it.type == AudioDeviceInfo.TYPE_BLE_SPEAKER
                }
                if (btDevice != null) {
                    audioManager.setCommunicationDevice(btDevice)
                } else {
                    audioManager.stopBluetoothSco()
                    @Suppress("DEPRECATION")
                    audioManager.isBluetoothScoOn = false
                    val speaker = audioManager.availableCommunicationDevices
                        .firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                    if (speaker != null) {
                        audioManager.setCommunicationDevice(speaker)
                    } else {
                        // TYPE_BUILTIN_SPEAKER ro'yxatda yo'q (Telecom tranzitsiya paytida).
                        // clearCommunicationDevice + eski API orqali speaker yoqamiz.
                        audioManager.clearCommunicationDevice()
                        @Suppress("DEPRECATION")
                        audioManager.isSpeakerphoneOn = true
                    }
                }
            } else {
                // BT SCO ni to'xtatamiz — aks holda earpiece'ga o'tish ishlamaydi
                audioManager.stopBluetoothSco()
                @Suppress("DEPRECATION")
                audioManager.isBluetoothScoOn = false
                audioManager.clearCommunicationDevice()
                @Suppress("DEPRECATION")
                audioManager.isSpeakerphoneOn = false
                // BT o'chgandan keyin earpiece/wired qurilma mavjud bo'lsa — belgilaymiz
                val earpiece = audioManager.availableCommunicationDevices.firstOrNull {
                    it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                    it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                    it.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                    it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
                }
                if (earpiece != null) {
                    audioManager.setCommunicationDevice(earpiece)
                }
            }
        } else {
            // Android 12 dan oldin
            if (speakerOn) {
                @Suppress("DEPRECATION")
                val btOn = audioManager.isBluetoothScoOn
                if (!btOn) {
                    audioManager.stopBluetoothSco()
                    @Suppress("DEPRECATION")
                    audioManager.isBluetoothScoOn = false
                    @Suppress("DEPRECATION")
                    audioManager.isSpeakerphoneOn = true
                }
            } else {
                @Suppress("DEPRECATION")
                audioManager.isSpeakerphoneOn = false
            }
        }

        @Suppress("DEPRECATION")
        audioManager.isMicrophoneMute = false
        volumeControlStream = AudioManager.STREAM_VOICE_CALL
        return getAudioRouteInfo()
    }

    private fun activateBluetooth() {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val btDevice = audioManager.availableCommunicationDevices.firstOrNull {
                it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                it.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                it.type == AudioDeviceInfo.TYPE_BLE_SPEAKER
            }
            if (btDevice != null) audioManager.setCommunicationDevice(btDevice)
        } else {
            @Suppress("DEPRECATION")
            audioManager.isSpeakerphoneOn = false
            audioManager.startBluetoothSco()
            @Suppress("DEPRECATION")
            audioManager.isBluetoothScoOn = true
        }
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
        } || audioManager.isBluetoothScoOn ||
            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                audioManager.availableCommunicationDevices.any {
                    it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                    it.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                    it.type == AudioDeviceInfo.TYPE_BLE_SPEAKER
                })

        val hasHeadset = outputs.any {
            it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                it.type == AudioDeviceInfo.TYPE_USB_HEADSET
        } || audioManager.isWiredHeadsetOn

        val currentRoute = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+: setCommunicationDevice natijasini to'g'ri o'qiymiz
            when (audioManager.communicationDevice?.type) {
                AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "speaker"
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                AudioDeviceInfo.TYPE_BLE_HEADSET,
                AudioDeviceInfo.TYPE_BLE_SPEAKER -> "bluetooth"
                AudioDeviceInfo.TYPE_WIRED_HEADSET,
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                AudioDeviceInfo.TYPE_USB_HEADSET -> "headset"
                else -> {
                    // communicationDevice null yoki noma'lum (Telecom tranzitsiya paytida).
                    // isSpeakerphoneOn fallback — activateCallAudio fallback bilan mos.
                    @Suppress("DEPRECATION")
                    if (audioManager.isSpeakerphoneOn) "speaker" else "earpiece"
                }
            }
        } else {
            @Suppress("DEPRECATION")
            when {
                audioManager.isSpeakerphoneOn -> "speaker"
                hasBluetooth -> "bluetooth"
                hasHeadset -> "headset"
                else -> "earpiece"
            }
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
