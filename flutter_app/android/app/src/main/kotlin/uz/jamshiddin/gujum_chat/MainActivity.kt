package uz.jamshiddin.gujum_chat

import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import com.google.android.gms.auth.api.identity.GetPhoneNumberHintIntentRequest
import com.google.android.gms.auth.api.identity.Identity
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
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
    private var phoneHintResult: MethodChannel.Result? = null

    // Qo'ng'iroq davomida quloqchin ulanishi/uzilishini kuzatish uchun.
    private var callAudioChannel: MethodChannel? = null
    private var audioDeviceCallback: AudioDeviceCallback? = null
    private var callAudioActive = false
    private var lastRoute = "auto"

    companion object {
        private const val REQ_PHONE_HINT = 7301
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        callAudioChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "gujum/call_audio"
        )
        callAudioChannel!!.setMethodCallHandler { call, result ->
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
                        activateCallAudio(call.argument<String>("route") ?: "auto")
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
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "gujum/media_save"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToGallery" -> saveMedia(call, result, toGallery = true)
                "saveToDownloads" -> saveMedia(call, result, toGallery = false)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "gujum/call_service"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    CallForegroundService.start(
                        applicationContext,
                        call.argument<String>("title") ?: "Gujum",
                        call.argument<String>("text") ?: "Qo'ng'iroq davom etmoqda",
                        call.argument<Boolean>("isVideo") ?: false
                    )
                    result.success(null)
                }
                "stop" -> {
                    CallForegroundService.stop(applicationContext)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "gujum/phone_hint"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPhoneNumberHint" -> requestPhoneNumberHint(result)
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Qurilmadagi SIM raqamlarini tizim tanlagichida ko'rsatadi (ikki SIM bo'lsa
     * ikkalasi ham chiqadi). Hech qanday ruxsat so'ralmaydi — foydalanuvchi
     * o'zi tanlaydi. Tanlanmasa yoki qurilma qo'llab-quvvatlamasa null qaytadi
     * va Flutter tomonda oddiy raqam kiritish oynasi ko'rsatiladi.
     */

    /**
     * Faylni tizim galereyasiga yoki Downloads papkasiga nusxalaydi.
     *
     * Android 10 dan boshlab ilova ochiq papkalarga to'g'ridan-to'g'ri yoza
     * olmaydi, lekin MediaStore orqali yozish uchun hech qanday ruxsat ham
     * so'ralmaydi. Eski versiyalarda esa oddiy fayl nusxalash ishlatiladi va
     * fayl galereyada ko'rinishi uchun MediaScanner ga xabar beriladi.
     */
    private fun saveMedia(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result,
        toGallery: Boolean,
    ) {
        val sourcePath = call.argument<String>("path")
        val fileName = call.argument<String>("fileName") ?: "gujum_file"
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"

        if (sourcePath.isNullOrBlank()) {
            result.error("no_path", "path kerak", null)
            return
        }
        val source = File(sourcePath)
        if (!source.exists()) {
            result.error("not_found", "Fayl topilmadi", null)
            return
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val collection = when {
                    !toGallery -> MediaStore.Downloads.EXTERNAL_CONTENT_URI
                    mimeType.startsWith("video") ->
                        MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                    else -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                }
                // Telegram singari: rasm va videolar alohida albomga tushadi,
                // hujjatlar esa Downloads ichiga.
                val relative = when {
                    !toGallery -> "${Environment.DIRECTORY_DOWNLOADS}/Gujum"
                    mimeType.startsWith("video") -> "${Environment.DIRECTORY_MOVIES}/Gujum"
                    else -> "${Environment.DIRECTORY_PICTURES}/Gujum"
                }
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, relative)
                    // Yozish tugagunicha boshqa ilovalar faylni ko'rmasin.
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(collection, values)
                if (uri == null) {
                    result.error("insert_failed", "MediaStore yozuvi yaratilmadi", null)
                    return
                }
                contentResolver.openOutputStream(uri)?.use { out ->
                    source.inputStream().use { input -> input.copyTo(out) }
                } ?: run {
                    contentResolver.delete(uri, null, null)
                    result.error("open_failed", "Fayl yozilmadi", null)
                    return
                }
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
                result.success(uri.toString())
            } else {
                @Suppress("DEPRECATION")
                val baseDir = when {
                    !toGallery -> Environment.getExternalStoragePublicDirectory(
                        Environment.DIRECTORY_DOWNLOADS
                    )
                    mimeType.startsWith("video") ->
                        Environment.getExternalStoragePublicDirectory(
                            Environment.DIRECTORY_MOVIES
                        )
                    else -> Environment.getExternalStoragePublicDirectory(
                        Environment.DIRECTORY_PICTURES
                    )
                }
                val dir = File(baseDir, "Gujum")
                if (!dir.exists()) dir.mkdirs()
                val target = File(dir, fileName)
                source.inputStream().use { input ->
                    target.outputStream().use { out -> input.copyTo(out) }
                }
                // Galereya yangi faylni darhol ko'rsin.
                android.media.MediaScannerConnection.scanFile(
                    this, arrayOf(target.absolutePath), arrayOf(mimeType), null
                )
                result.success(target.absolutePath)
            }
        } catch (e: Exception) {
            result.error("save_failed", e.message, null)
        }
    }

    private fun requestPhoneNumberHint(result: MethodChannel.Result) {
        if (phoneHintResult != null) {
            result.success(null)
            return
        }
        try {
            val request = GetPhoneNumberHintIntentRequest.builder().build()
            Identity.getSignInClient(this)
                .getPhoneNumberHintIntent(request)
                .addOnSuccessListener { pendingIntent ->
                    try {
                        phoneHintResult = result
                        startIntentSenderForResult(
                            pendingIntent.intentSender,
                            REQ_PHONE_HINT,
                            null, 0, 0, 0
                        )
                    } catch (e: Exception) {
                        phoneHintResult = null
                        result.success(null)
                    }
                }
                .addOnFailureListener {
                    result.success(null)
                }
        } catch (e: Exception) {
            result.success(null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_PHONE_HINT) return
        val pending = phoneHintResult
        phoneHintResult = null
        if (pending == null) return
        if (resultCode != Activity.RESULT_OK || data == null) {
            pending.success(null)
            return
        }
        val number = try {
            Identity.getSignInClient(this).getPhoneNumberFromIntent(data)
        } catch (e: Exception) {
            null
        }
        pending.success(number)
    }

    // Bir joyda: quloqchin (simli yoki bluetooth) ulanganmi?
    // Ringtone/ringback speaker'ga majburlashdan oldin shu tekshiriladi —
    // aks holda quloqchin ulangan bo'lsa ham ovoz telefon dinamigidan chiqadi.
    private fun hasExternalAudioOutput(audioManager: AudioManager): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any {
                it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                it.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
            }
        }
        @Suppress("DEPRECATION")
        return audioManager.isWiredHeadsetOn || audioManager.isBluetoothScoOn
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
        // Kiruvchi qo'ng'iroq ringtone'i ham quloqchinga boradi, agar u ulangan bo'lsa.
        @Suppress("DEPRECATION")
        audioManager?.isSpeakerphoneOn =
            audioManager?.let { !hasExternalAudioOutput(it) } ?: true
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
        // Quloqchin ulangan bo'lsa speaker'ni yoqmaymiz — "tuu...tuu" ringback
        // quloqchindan chiqishi kerak, telefon dinamigidan emas.
        @Suppress("DEPRECATION")
        audioManager?.isSpeakerphoneOn =
            audioManager?.let { !hasExternalAudioOutput(it) } ?: true
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

    /**
     * Qo'ng'iroq paytida audio qurilmalar o'zgarishini kuzatadi.
     *
     * Ilgari marshrut faqat qo'ng'iroq boshida hisoblanardi: suhbat davomida
     * simli quloqchin ulansa hech narsa o'zgarmasdi va ovoz dinamikda qolardi.
     * Endi qurilma qo'shilganda yoki uzilganda marshrut qayta hisoblanadi va
     * natija Flutter tomonga yuboriladi.
     */
    private fun startAudioDeviceWatch() {
        if (audioDeviceCallback != null) return
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        val callback = object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
                reapplyCallAudio()
            }

            override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
                reapplyCallAudio()
            }
        }
        audioDeviceCallback = callback
        audioManager.registerAudioDeviceCallback(callback, null)
    }

    private fun stopAudioDeviceWatch() {
        val callback = audioDeviceCallback ?: return
        audioDeviceCallback = null
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        audioManager.unregisterAudioDeviceCallback(callback)
    }

    private fun reapplyCallAudio() {
        if (!callAudioActive) return
        // Tizim qurilma ro'yxatini yangilashi uchun qisqa kechikish — aks holda
        // yangi ulangan quloqchin hali availableCommunicationDevices da yo'q.
        window.decorView.postDelayed({
            if (!callAudioActive) return@postDelayed
            val info = activateCallAudio(lastRoute)
            callAudioChannel?.invokeMethod("audioRouteChanged", info)
        }, 350)
    }

    /**
     * Qo'ng'iroq audiosini berilgan marshrutga o'tkazadi.
     *
     * [route]: "auto" | "speaker" | "earpiece" | "headset" | "bluetooth".
     *
     * "auto" — foydalanuvchi hech narsa tanlamagan holat: ulangan bluetooth
     * yoki simli quloqchin avtomatik ustun bo'ladi. Qolgan qiymatlar aniq
     * tanlov: ular ulangan quloqchindan ham ustun turadi (masalan quloqchin
     * ulangan holda dinamikni yoqish). Ilgari bu yerda faqat `speakerOn`
     * bayrog'i bor edi va bitta tanlov ("speaker") butun sessiya davomida
     * quloqchin aniqlashni o'chirib qo'yardi — shu sababli suhbat o'rtasida
     * ulangan quloqchin e'tiborsiz qolardi.
     */
    private fun activateCallAudio(route: String): Map<String, Any> {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            ?: return mapOf(
                "currentRoute" to "speaker",
                "hasBluetooth" to false,
                "hasHeadset" to false,
            )

        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        lastRoute = route
        callAudioActive = true
        startAudioDeviceWatch()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val devices = audioManager.availableCommunicationDevices
            fun findOf(vararg types: Int) =
                devices.firstOrNull { device -> types.any { it == device.type } }

            val bluetooth = findOf(
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                AudioDeviceInfo.TYPE_BLE_HEADSET,
                AudioDeviceInfo.TYPE_BLE_SPEAKER,
            )
            val wired = findOf(
                AudioDeviceInfo.TYPE_WIRED_HEADSET,
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                AudioDeviceInfo.TYPE_USB_HEADSET,
            )
            val speaker = findOf(
                AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
                AudioDeviceInfo.TYPE_BUILTIN_SPEAKER_SAFE,
            )
            // Quloqchin ulangan bo'lsa "earpiece" jismonan quloqchinga boradi —
            // shuning uchun u yerda ham wired ustun.
            val earpiece = wired ?: findOf(AudioDeviceInfo.TYPE_BUILTIN_EARPIECE)

            val target = when (route) {
                "speaker" -> speaker
                "bluetooth" -> bluetooth
                "headset" -> wired ?: bluetooth
                "earpiece" -> earpiece
                else -> bluetooth ?: wired ?: earpiece
            } ?: (bluetooth ?: wired ?: earpiece ?: speaker)

            val isSpeakerTarget = target != null && (
                target.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER ||
                target.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER_SAFE
            )
            val isBluetoothTarget = target != null && (
                target.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                target.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                target.type == AudioDeviceInfo.TYPE_BLE_SPEAKER
            )

            if (!isBluetoothTarget) {
                audioManager.stopBluetoothSco()
                @Suppress("DEPRECATION")
                audioManager.isBluetoothScoOn = false
            }
            @Suppress("DEPRECATION")
            audioManager.isSpeakerphoneOn = isSpeakerTarget

            if (target != null) {
                // Bir xil qurilmani qayta o'rnatish ba'zi qurilmalarda audio
                // uzilishiga olib keladi — faqat o'zgarganda chaqiramiz.
                if (audioManager.communicationDevice?.id != target.id) {
                    audioManager.setCommunicationDevice(target)
                }
            } else {
                audioManager.clearCommunicationDevice()
            }
        } else {
            when (route) {
                "speaker" -> {
                    audioManager.stopBluetoothSco()
                    @Suppress("DEPRECATION")
                    audioManager.isBluetoothScoOn = false
                    @Suppress("DEPRECATION")
                    audioManager.isSpeakerphoneOn = true
                }
                "bluetooth" -> {
                    @Suppress("DEPRECATION")
                    audioManager.isSpeakerphoneOn = false
                    audioManager.startBluetoothSco()
                    @Suppress("DEPRECATION")
                    audioManager.isBluetoothScoOn = true
                }
                else -> {
                    // "auto"/"headset"/"earpiece": quloqchin ulangan bo'lsa tizim
                    // o'zi unga yo'naltiradi, dinamikni o'chirish kifoya.
                    if (route != "auto" || !audioManager.isBluetoothScoOn) {
                        audioManager.stopBluetoothSco()
                        @Suppress("DEPRECATION")
                        audioManager.isBluetoothScoOn = false
                    }
                    @Suppress("DEPRECATION")
                    audioManager.isSpeakerphoneOn = false
                }
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
        callAudioActive = false
        stopAudioDeviceWatch()
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
                AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
                AudioDeviceInfo.TYPE_BUILTIN_SPEAKER_SAFE -> "speaker"
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
