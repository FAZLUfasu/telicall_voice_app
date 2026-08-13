package com.example.telicall_voice_app

import android.Manifest
import android.app.role.RoleManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.telecom.TelecomManager
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import androidx.core.content.FileProvider

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL = "com.example.telicall_voice_app/telecom"

        private const val REQUEST_CALL_PHONE = 1001
        private const val REQUEST_ANSWER_PHONE = 1002
    }

    private var methodChannel: MethodChannel? = null
    private var callStateReceiver: BroadcastReceiver? = null
    private var isAiModeActive = false

    // Chunk Recorder Fields
    private var chunkIndex = 0
    private var currentChunkFile: File? = null
    private var currentChunkOutputStream: FileOutputStream? = null
    private var bytesRecordedInChunk = 0
    private val CHUNK_MAX_BYTES = 16000 * 2 * 3 // ~3 seconds per chunk file (16kHz 16-bit Mono)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )

        registerCallReceiver()
        setupMethodChannel()
    }

    // ============================================================
    // BROADCAST RECEIVER
    // ============================================================

    private fun registerCallReceiver() {
        callStateReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    "com.example.telicall_voice_app.CALL_ANSWERED" -> {
                        println("📞 [NATIVE] CALL_ANSWERED received")
                        startNewChunkFile()
                        methodChannel?.invokeMethod("onCallAnswered", null)
                    }

                    "com.example.telicall_voice_app.CALL_ENDED" -> {
                        println("🔴 [NATIVE] CALL_ENDED received")
                        finalizeChunkFile()
                        methodChannel?.invokeMethod("onCallEnded", null)
                    }

                    "com.example.telicall_voice_app.PCM_DOWNLINK_FRAME" -> {
                        val pcm = intent.getByteArrayExtra("pcm_bytes")
                        if (pcm != null && pcm.isNotEmpty()) {
                            // 1. Record PCM locally to verify captured customer voice quality
                            writePcmToChunk(pcm)

                            // 2. Stream PCM to Flutter Dart layer / WebSocket pipe
                            methodChannel?.invokeMethod("onCallerAudioReceived", pcm)
                        }
                    }
                }
            }
        }

        val filter = IntentFilter().apply {
            addAction("com.example.telicall_voice_app.CALL_ANSWERED")
            addAction("com.example.telicall_voice_app.CALL_ENDED")
            addAction("com.example.telicall_voice_app.PCM_DOWNLINK_FRAME")
        }

        // 🔑 MUST use RECEIVER_EXPORTED on API 33+ for cross-process Telecom broadcasts
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(
                callStateReceiver,
                filter,
                Context.RECEIVER_EXPORTED
            )
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(
                callStateReceiver,
                filter
            )
        }
    }

    // ============================================================
    // FLUTTER METHOD CHANNEL
    // ============================================================

    private fun setupMethodChannel() {
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                // ------------------------------------------------
                // AUDIO INSPECTOR APIs
                // ------------------------------------------------
                "getRecordedChunks" -> {
                    val recordDir = File(getExternalFilesDir(null), "recorded_chunks")
                    val fileList = recordDir.listFiles()?.map { it.absolutePath } ?: emptyList()
                    result.success(fileList)
                }

                "clearRecordedChunks" -> {
                    val recordDir = File(getExternalFilesDir(null), "recorded_chunks")
                    recordDir.listFiles()?.forEach { it.delete() }
                    chunkIndex = 0
                    result.success(true)
                }

                // ------------------------------------------------
                // MAKE CALL
                // ------------------------------------------------
                "makeNativeInternalCall" -> {
                    val number = call.argument<String>("phoneNumber")
                    isAiModeActive = call.argument<Boolean>("isAiMode") ?: false

                    if (number.isNullOrBlank()) {
                        result.error("INVALID_NUMBER", "Phone number is empty", null)
                        return@setMethodCallHandler
                    }

                    if (ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.CALL_PHONE
                        ) != PackageManager.PERMISSION_GRANTED
                    ) {
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.CALL_PHONE),
                            REQUEST_CALL_PHONE
                        )
                        result.error("CALL_PERMISSION", "CALL_PHONE permission required", null)
                        return@setMethodCallHandler
                    }

                    if (isAiModeActive) {
                        applyAiAudioMode()
                    } else {
                        restoreNormalAudio()
                    }

                    val success = makeDirectTelecomCall(number)
                    result.success(success)
                }


                
               "shareRecordedChunk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        val file = File(filePath)
                        if (file.exists()) {
                            try {
                                // 1. Generate content:// URI via FileProvider
                                val uri = FileProvider.getUriForFile(
                                    this,
                                    "$packageName.fileprovider",
                                    file
                                )

                                // 2. Build explicit ACTION_SEND Intent
                                val shareIntent = Intent(Intent.ACTION_SEND).apply {
                                    type = "audio/x-wav" // 🔑 Works across WhatsApp, Telegram, Drive
                                    putExtra(Intent.EXTRA_STREAM, uri)
                                    putExtra(Intent.EXTRA_SUBJECT, "Call Recording")
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }

                                // 3. Create Chooser
                                val chooserIntent = Intent.createChooser(shareIntent, "Share WAV Recording").apply {
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }

                                // 4. Grant explicit URI permissions to any app handling the chooser
                                val resInfoList = packageManager.queryIntentActivities(
                                    chooserIntent,
                                    android.content.pm.PackageManager.MATCH_DEFAULT_ONLY
                                )
                                for (resolveInfo in resInfoList) {
                                    val packageName = resolveInfo.activityInfo.packageName
                                    grantUriPermission(
                                        packageName,
                                        uri,
                                        Intent.FLAG_GRANT_READ_URI_PERMISSION
                                    )
                                }

                                startActivity(chooserIntent)
                                result.success(true)

                            } catch (e: Exception) {
                                Log.e("MainActivity", "❌ Share failed", e)
                                result.error("SHARE_ERROR", e.message, null)
                            }
                        } else {
                            result.error("FILE_NOT_FOUND", "WAV file does not exist", null)
                        }
                    } else {
                        result.error("INVALID_PATH", "File path is null", null)
                    }
                }
                // ------------------------------------------------
                // AI AUDIO MODE
                // ------------------------------------------------
                "setAudioMode" -> {
                    val aiMode = call.argument<Boolean>("isAiMode") ?: false
                    isAiModeActive = aiMode

                    if (aiMode) {
                        applyAiAudioMode()
                    } else {
                        restoreNormalAudio()
                    }

                    result.success(true)
                }

                // ------------------------------------------------
                // AI AUDIO INJECTION
                // ------------------------------------------------
                "playAiAudioChunk" -> {
                    val pcmData = call.argument<ByteArray>("pcmData")
                    val wavPath = call.argument<String>("filePath")

                    if (pcmData == null && wavPath.isNullOrBlank()) {
                        result.error("INVALID_AUDIO", "PCM data or WAV path missing", null)
                        return@setMethodCallHandler
                    }

                    val intent = Intent("com.example.telicall_voice_app.INJECT_UPLINK_AUDIO").apply {
                        setPackage(packageName)
                        putExtra("pcm_data", pcmData)
                        putExtra("wav_path", wavPath)
                    }

                    sendBroadcast(intent)
                    result.success(true)
                }

                // ------------------------------------------------
                // HANG UP
                // ------------------------------------------------
                "disconnectCall" -> {
                    isAiModeActive = false
                    restoreNormalAudio()
                    result.success(hangUpActiveCall())
                }

                // ------------------------------------------------
                // CHECK DIALER ROLE
                // ------------------------------------------------
                "checkDialerStatus" -> {
                    result.success(checkDialerRole())
                }

                // ------------------------------------------------
                // REQUEST DIALER ROLE
                // ------------------------------------------------
                "requestDefaultDialer",
                "requestDialerRole" -> {
                    requestDefaultDialerRole()
                    result.success(true)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    // ============================================================
    // CHUNK WAV RECORDING LOGIC FOR AUDIO QUALITY VERIFICATION
    // ============================================================

    private fun startNewChunkFile() {
        finalizeChunkFile()
        try {
            val recordDir = File(getExternalFilesDir(null), "recorded_chunks")
            if (!recordDir.exists()) recordDir.mkdirs()

            chunkIndex++
            currentChunkFile = File(recordDir, "call_chunk_$chunkIndex.wav")
            currentChunkOutputStream = FileOutputStream(currentChunkFile)
            bytesRecordedInChunk = 0

            // Write temporary 44-byte placeholder WAV header
            currentChunkOutputStream?.write(ByteArray(44))
            Log.d(TAG, "🎙 Started recording chunk: ${currentChunkFile?.name}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create chunk file", e)
        }
    }

    private fun writePcmToChunk(pcmBytes: ByteArray) {
        try {
            if (currentChunkOutputStream == null) {
                startNewChunkFile()
            }

            currentChunkOutputStream?.write(pcmBytes)
            bytesRecordedInChunk += pcmBytes.size

            if (bytesRecordedInChunk >= CHUNK_MAX_BYTES) {
                startNewChunkFile()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error writing PCM frame to chunk", e)
        }
    }

    private fun finalizeChunkFile() {
        try {
            currentChunkOutputStream?.flush()
            currentChunkOutputStream?.close()
            currentChunkOutputStream = null

            currentChunkFile?.let { file ->
                if (file.exists() && bytesRecordedInChunk > 0) {
                    writeWavHeader(file, bytesRecordedInChunk)
                    Log.d(TAG, "✅ Saved chunk file: ${file.name} ($bytesRecordedInChunk bytes)")
                    runOnUiThread {
                        methodChannel?.invokeMethod("onNewChunkSaved", file.absolutePath)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error finalizing chunk WAV file", e)
        }
    }

    private fun writeWavHeader(file: File, pcmDataLength: Int) {
        val totalDataLen = pcmDataLength + 36
        val sampleRate = 16000
        val channels = 1
        val byteRate = sampleRate * channels * 2

        val header = ByteArray(44)
        header[0] = 'R'.code.toByte()
        header[1] = 'I'.code.toByte()
        header[2] = 'F'.code.toByte()
        header[3] = 'F'.code.toByte()
        header[4] = (totalDataLen and 0xff).toByte()
        header[5] = (totalDataLen shr 8 and 0xff).toByte()
        header[6] = (totalDataLen shr 16 and 0xff).toByte()
        header[7] = (totalDataLen shr 24 and 0xff).toByte()
        header[8] = 'W'.code.toByte()
        header[9] = 'A'.code.toByte()
        header[10] = 'V'.code.toByte()
        header[11] = 'E'.code.toByte()
        header[12] = 'f'.code.toByte()
        header[13] = 'm'.code.toByte()
        header[14] = 't'.code.toByte()
        header[15] = ' '.code.toByte()
        header[16] = 16
        header[17] = 0
        header[18] = 0
        header[19] = 0
        header[20] = 1
        header[21] = 0
        header[22] = channels.toByte()
        header[23] = 0
        header[24] = (sampleRate and 0xff).toByte()
        header[25] = (sampleRate shr 8 and 0xff).toByte()
        header[26] = (sampleRate shr 16 and 0xff).toByte()
        header[27] = (sampleRate shr 24 and 0xff).toByte()
        header[28] = (byteRate and 0xff).toByte()
        header[29] = (byteRate shr 8 and 0xff).toByte()
        header[30] = (byteRate shr 16 and 0xff).toByte()
        header[31] = (byteRate shr 24 and 0xff).toByte()
        header[32] = 2
        header[33] = 0
        header[34] = 16
        header[35] = 0
        header[36] = 'd'.code.toByte()
        header[37] = 'a'.code.toByte()
        header[38] = 't'.code.toByte()
        header[39] = 'a'.code.toByte()
        header[40] = (pcmDataLength and 0xff).toByte()
        header[41] = (pcmDataLength shr 8 and 0xff).toByte()
        header[42] = (pcmDataLength shr 16 and 0xff).toByte()
        header[43] = (pcmDataLength shr 24 and 0xff).toByte()

        val raf = RandomAccessFile(file, "rw")
        raf.seek(0)
        raf.write(header)
        raf.close()
    }

    // ============================================================
    // CHECK DIALER ROLE
    // ============================================================

    private fun checkDialerRole(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roleManager = getSystemService(Context.ROLE_SERVICE) as RoleManager
            roleManager.isRoleHeld(RoleManager.ROLE_DIALER)
        } else {
            val telecom = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            packageName == telecom.defaultDialerPackage
        }
    }

    // ============================================================
    // REQUEST DIALER ROLE
    // ============================================================

    private fun requestDefaultDialerRole() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roleManager = getSystemService(Context.ROLE_SERVICE) as RoleManager

            println("☎️ DIALER ROLE AVAILABLE = " + roleManager.isRoleAvailable(RoleManager.ROLE_DIALER))
            println("☎️ DIALER ROLE HELD = " + roleManager.isRoleHeld(RoleManager.ROLE_DIALER))

            if (roleManager.isRoleAvailable(RoleManager.ROLE_DIALER) &&
                !roleManager.isRoleHeld(RoleManager.ROLE_DIALER)
            ) {
                val intent = roleManager.createRequestRoleIntent(RoleManager.ROLE_DIALER)
                startActivityForResult(intent, 5001)
            }
        } else {
            try {
                val intent = Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS)
                startActivity(intent)
            } catch (e: Exception) {
                println("❌ Failed to open default apps: " + e.message)
            }
        }
    }

    // ============================================================
    // PLACE CALL
    // ============================================================

    private fun makeDirectTelecomCall(number: String): Boolean {
        var cleanNumber = number.replace("[^0-9+]".toRegex(), "")

        if (cleanNumber.length == 10 && !cleanNumber.startsWith("+")) {
            cleanNumber = "+91$cleanNumber"
        }

        val uri = Uri.parse("tel:$cleanNumber")

        return try {
            val telecom = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            val extras = Bundle()

            val accounts = telecom.callCapablePhoneAccounts
            if (accounts != null && accounts.isNotEmpty()) {
                extras.putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, accounts[0])
                println("📱 Using SIM account: " + accounts[0])
            } else {
                val selected = telecom.getUserSelectedOutgoingPhoneAccount()
                if (selected != null) {
                    extras.putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, selected)
                }
            }

            extras.putBoolean(TelecomManager.EXTRA_START_CALL_WITH_SPEAKERPHONE, false)
            telecom.placeCall(uri, extras)
            println("📞 [TELECOM] Call placed: $cleanNumber")
            true
        } catch (e: Exception) {
            println("❌ Telecom placeCall failed: " + e.message)
            false
        }
    }

    // ============================================================
    // HANG UP
    // ============================================================

    private fun hangUpActiveCall(): Boolean {
        return try {
            val telecom = getSystemService(Context.TELECOM_SERVICE) as TelecomManager

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                if (ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.ANSWER_PHONE_CALLS
                    ) != PackageManager.PERMISSION_GRANTED
                ) {
                    ActivityCompat.requestPermissions(
                        this,
                        arrayOf(Manifest.permission.ANSWER_PHONE_CALLS),
                        REQUEST_ANSWER_PHONE
                    )
                    return false
                }
            }

            telecom.endCall()
            println("🔴 [TELECOM] Call ended")
            true
        } catch (e: Exception) {
            println("❌ End call failed: " + e.message)
            false
        }
    }

    // ============================================================
    // AI AUDIO MODE
    // ============================================================

    private fun applyAiAudioMode() {
        try {
            val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audio.mode = AudioManager.MODE_IN_CALL
            audio.isSpeakerphoneOn = false
            audio.isMicrophoneMute = false

            val maxVolume = audio.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)
            audio.setStreamVolume(AudioManager.STREAM_VOICE_CALL, maxVolume, 0)
            println("🔊 AI audio mode enabled")
        } catch (e: Exception) {
            println("⚠️ AI audio mode error: " + e.message)
        }
    }

    // ============================================================
    // NORMAL AUDIO
    // ============================================================

    private fun restoreNormalAudio() {
        try {
            val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audio.mode = AudioManager.MODE_IN_CALL
            audio.isMicrophoneMute = false

            val maxVolume = audio.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)
            audio.setStreamVolume(AudioManager.STREAM_VOICE_CALL, maxVolume / 2, 0)
        } catch (e: Exception) {
            println("⚠️ Restore audio error: " + e.message)
        }
    }

    // ============================================================
    // ACTIVITY RESULT
    // ============================================================

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == 5001) {
            val isDialer = checkDialerRole()
            println("☎️ Dialer role result = $isDialer")
            methodChannel?.invokeMethod("dialerRoleChanged", isDialer)
        }
    }

    // ============================================================
    // CLEANUP
    // ============================================================

    override fun onDestroy() {
        callStateReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {}
        }
        methodChannel = null
        super.onDestroy()
    }
}