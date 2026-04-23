package com.example.bootchat_flutter

import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var incomingRingtone: Ringtone? = null

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

    override fun onDestroy() {
        stopIncomingRingtone()
        incomingRingtone = null
        super.onDestroy()
    }
}
