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
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile

class MainActivity : FlutterActivity() {

    companion object {

        private const val TAG = "MainActivity"

        private const val CHANNEL =
            "com.example.telicall_voice_app/telecom"

        private const val REQUEST_CALL_PHONE = 1001
        private const val REQUEST_ANSWER_PHONE = 1002

        /*
         * Static MethodChannel used by AppInCallService
         */
        private var _methodChannel: MethodChannel? = null

        @JvmStatic
        fun getMethodChannel(): MethodChannel? {
            return _methodChannel
        }

        /*
         * Central logging helpers
         */
        @JvmStatic
        fun nativeLog(message: String) {
            Log.d(TAG, "📱 MA $message")
        }

        @JvmStatic
        fun nativeLogError(message: String, throwable: Throwable? = null) {
            if (throwable != null) {
                Log.e(TAG, "❌ MA $message", throwable)
            } else {
                Log.e(TAG, "❌ MA $message")
            }
        }
    }

    // ============================================================
    // STATE
    // ============================================================

    private var callStateReceiver: BroadcastReceiver? = null

    private var isAiModeActive = false

    // ============================================================
    // CHUNK RECORDER
    // ============================================================

    private var chunkIndex = 0

    private var currentChunkFile: File? = null

    private var currentChunkOutputStream: FileOutputStream? = null

    private var bytesRecordedInChunk = 0

    private var totalPcmBytesRecorded = 0L

    private var totalChunksCreated = 0

    /*
     * 16 kHz
     * 16-bit
     * Mono
     * 3 seconds
     *
     * 16000 * 2 * 3 = 96000 bytes
     */
    private val CHUNK_MAX_BYTES =
        16000 * 2 * 3

    // ============================================================
    // ACTIVITY CREATED
    // ============================================================

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        Log.d(
            TAG,
            "================================================"
        )

        Log.d(
            TAG,
            "📱 MA MainActivity onCreate()"
        )

        Log.d(
            TAG,
            "📱 MA Package = $packageName"
        )

        Log.d(
            TAG,
            "📱 MA Android SDK = ${Build.VERSION.SDK_INT}"
        )

        Log.d(
            TAG,
            "📱 MA Device = ${Build.MANUFACTURER} ${Build.MODEL}"
        )

        Log.d(
            TAG,
            "================================================"
        )
    }

    // ============================================================
    // FLUTTER ENGINE
    // ============================================================

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
        super.configureFlutterEngine(flutterEngine)

        Log.d(
            TAG,
            "📱 MA configureFlutterEngine() START"
        )

        /*
         * Create MethodChannel
         */
        _methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )

        Log.d(
            TAG,
            "📱 MA MethodChannel CREATED"
        )

        Log.d(
            TAG,
            "📱 MA Channel = $CHANNEL"
        )

        registerCallReceiver()

        setupMethodChannel()

        Log.d(
            TAG,
            "📱 MA configureFlutterEngine() COMPLETE"
        )
    }

    // ============================================================
    // BROADCAST RECEIVER
    // ============================================================

    private fun registerCallReceiver() {

        Log.d(
            TAG,
            "📡 MA Registering call-state BroadcastReceiver"
        )

        callStateReceiver = object : BroadcastReceiver() {

            override fun onReceive(
                context: Context?,
                intent: Intent?
            ) {

                val action = intent?.action

                Log.d(
                    TAG,
                    "📡 MA Broadcast received"
                )

                Log.d(
                    TAG,
                    "📡 MA Action = $action"
                )

                when (action) {

                    "com.example.telicall_voice_app.CALL_ANSWERED" -> {

                        Log.d(
                            TAG,
                            "================================================"
                        )

                        Log.d(
                            TAG,
                            "📞 MA CALL_ANSWERED RECEIVED"
                        )

                        Log.d(
                            TAG,
                            "📞 MA AI Mode Active = $isAiModeActive"
                        )

                        startNewChunkFile()

                        try {
                            getMethodChannel()?.invokeMethod(
                                "onCallAnswered",
                                null
                            )

                            Log.d(
                                TAG,
                                "📱 MA Flutter callback sent: onCallAnswered"
                            )

                        } catch (e: Exception) {

                            Log.e(
                                TAG,
                                "❌ MA Failed Flutter callback onCallAnswered",
                                e
                            )
                        }

                        Log.d(
                            TAG,
                            "================================================"
                        )
                    }

                    "com.example.telicall_voice_app.CALL_ENDED" -> {

                        Log.d(
                            TAG,
                            "================================================"
                        )

                        Log.d(
                            TAG,
                            "🔴 MA CALL_ENDED RECEIVED"
                        )

                        Log.d(
                            TAG,
                            "🔴 MA Current chunk bytes = $bytesRecordedInChunk"
                        )

                        Log.d(
                            TAG,
                            "🔴 MA Total PCM bytes = $totalPcmBytesRecorded"
                        )

                        finalizeChunkFile()

                        try {

                            getMethodChannel()?.invokeMethod(
                                "onCallEnded",
                                null
                            )

                            Log.d(
                                TAG,
                                "📱 MA Flutter callback sent: onCallEnded"
                            )

                        } catch (e: Exception) {

                            Log.e(
                                TAG,
                                "❌ MA Failed Flutter callback onCallEnded",
                                e
                            )
                        }

                        Log.d(
                            TAG,
                            "================================================"
                        )
                    }

                    else -> {

                        Log.d(
                            TAG,
                            "📡 MA Unknown broadcast action: $action"
                        )
                    }
                }
            }
        }

        val filter = IntentFilter().apply {

            addAction(
                "com.example.telicall_voice_app.CALL_ANSWERED"
            )

            addAction(
                "com.example.telicall_voice_app.CALL_ENDED"
            )
        }

        try {

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {

                registerReceiver(
                    callStateReceiver,
                    filter,
                    Context.RECEIVER_EXPORTED
                )

                Log.d(
                    TAG,
                    "📡 MA Receiver registered using RECEIVER_EXPORTED"
                )

            } else {

                @Suppress("DEPRECATION")
                registerReceiver(
                    callStateReceiver,
                    filter
                )

                Log.d(
                    TAG,
                    "📡 MA Receiver registered using legacy API"
                )
            }

        } catch (e: Exception) {

            Log.e(
                TAG,
                "❌ MA Failed to register BroadcastReceiver",
                e
            )
        }
    }

    // ============================================================
    // METHOD CHANNEL
    // ============================================================

    private fun setupMethodChannel() {

        Log.d(
            TAG,
            "📱 MA Setting up Flutter MethodChannel handler"
        )

        getMethodChannel()?.setMethodCallHandler {
            call,
            result ->

            Log.d(
                TAG,
                "================================================"
            )

            Log.d(
                TAG,
                "📲 MA METHOD CALL RECEIVED"
            )

            Log.d(
                TAG,
                "📲 MA Method = ${call.method}"
            )

            Log.d(
                TAG,
                "📲 MA Arguments = ${call.arguments}"
            )

            when (call.method) {

                // ==================================================
                // GET RECORDED CHUNKS
                // ==================================================

                "getRecordedChunks" -> {

                        Log.d(
                            TAG,
                            "🎙 MA getRecordedChunks()"
                        )

                        try {

                            val recordDir =
                                File(
                                    getExternalFilesDir(null),
                                    "call_recordings"
                                )


                            Log.d(
                                TAG,
                                "🎙 Customer recording directory = ${recordDir.absolutePath}"
                            )


                            if (!recordDir.exists()) {

                                Log.w(
                                    TAG,
                                    "⚠️ Customer recording directory does not exist"
                                )

                                result.success(
                                    emptyList<String>()
                                )

                                return@setMethodCallHandler
                            }


                            val fileList =
                                recordDir
                                    .walkTopDown()
                                    .filter { file ->

                                        file.isFile &&
                                        file.extension.equals(
                                            "wav",
                                            ignoreCase = true
                                        ) &&

                                        // Show only final customer call recordings.
                                        file.name.startsWith(
                                            "customer_rx_session_"
                                        )
                                    }
                                    .sortedByDescending { file ->

                                        file.lastModified()
                                    }
                                    .map { file ->

                                        file.absolutePath
                                    }
                                    .toList()


                            Log.d(
                                TAG,
                                "🎙 Customer recordings found = ${fileList.size}"
                            )


                            fileList.forEach { filePath ->

                                Log.d(
                                    TAG,
                                    "🎙 CUSTOMER FILE = $filePath"
                                )
                            }


                            result.success(
                                fileList
                            )


                        } catch (e: Exception) {

                            Log.e(
                                TAG,
                                "❌ MA getRecordedChunks failed",
                                e
                            )


                            result.error(
                                "CHUNK_LIST_ERROR",
                                e.message,
                                null
                            )
                        }
                    }

                // ==================================================
                // CLEAR RECORDED CHUNKS
                // ==================================================

                "clearRecordedChunks" -> {

                            Log.d(
                                TAG,
                                "🧹 MA clearRecordedChunks()"
                            )

                            try {

                                val recordDir =
                                    File(
                                        getExternalFilesDir(null),
                                        "call_recordings"
                                    )


                                var deleted =
                                    0


                                if (recordDir.exists()) {

                                    recordDir
                                        .walkBottomUp()
                                        .forEach { file ->

                                            if (
                                                file.isFile &&
                                                file.extension.equals(
                                                    "wav",
                                                    ignoreCase = true
                                                )
                                            ) {

                                                if (file.delete()) {

                                                    deleted++

                                                    Log.d(
                                                        TAG,
                                                        "🧹 Deleted ${file.absolutePath}"
                                                    )
                                                }
                                            }
                                        }
                                }


                                Log.d(
                                    TAG,
                                    "🧹 Customer recordings deleted = $deleted"
                                )


                                result.success(
                                    true
                                )


                            } catch (e: Exception) {

                                Log.e(
                                    TAG,
                                    "❌ clearRecordedChunks failed",
                                    e
                                )


                                result.error(
                                    "CLEAR_ERROR",
                                    e.message,
                                    null
                                )
                            }
                        }

                // ==================================================
                // GET AI RESPONSE RECORDINGS
                // ==================================================

                "getAiResponseRecordings" -> {

                    Log.d(
                        TAG,
                        "🤖 MA getAiResponseRecordings()"
                    )

                    try {

                        val files =
                            getAiResponseRecordingFiles()

                        Log.d(
                            TAG,
                            "🤖 MA AI response files = ${files.size}"
                        )

                        result.success(
                            files.map { it.absolutePath }
                        )

                    } catch (e: Exception) {

                        Log.e(
                            TAG,
                            "❌ MA getAiResponseRecordings failed",
                            e
                        )

                        result.error(
                            "AI_RESPONSE_LIST_ERROR",
                            e.message,
                            null
                        )
                    }
                }

                // ==================================================
                // SHARE AI RESPONSE RECORDING
                // ==================================================

                "shareAiResponseRecording" -> {

                    val filePath =
                        call.argument<String>("filePath")

                    Log.d(
                        TAG,
                        "🤖📤 MA shareAiResponseRecording path=$filePath"
                    )

                    if (filePath.isNullOrBlank()) {

                        result.error(
                            "INVALID_PATH",
                            "AI response file path is empty",
                            null
                        )

                        return@setMethodCallHandler
                    }

                    try {

                        val file =
                            File(filePath)

                        if (!isValidAiResponseFile(file)) {

                            result.error(
                                "INVALID_AI_RESPONSE_FILE",
                                "File is outside the AI response recording directory",
                                null
                            )

                            return@setMethodCallHandler
                        }

                        if (!file.exists() || !file.isFile) {

                            result.error(
                                "FILE_NOT_FOUND",
                                "AI response WAV file does not exist",
                                null
                            )

                            return@setMethodCallHandler
                        }

                        val uri =
                            FileProvider.getUriForFile(
                                this,
                                "$packageName.fileprovider",
                                file
                            )

                        val shareIntent =
                            Intent(
                                Intent.ACTION_SEND
                            ).apply {

                                type = "audio/x-wav"

                                putExtra(
                                    Intent.EXTRA_STREAM,
                                    uri
                                )

                                putExtra(
                                    Intent.EXTRA_SUBJECT,
                                    "AI Response Audio"
                                )

                                addFlags(
                                    Intent.FLAG_GRANT_READ_URI_PERMISSION
                                )
                            }

                        val chooserIntent =
                            Intent.createChooser(
                                shareIntent,
                                "Share AI Response Audio"
                            ).apply {

                                addFlags(
                                    Intent.FLAG_GRANT_READ_URI_PERMISSION
                                )
                            }

                        val resInfoList =
                            packageManager.queryIntentActivities(
                                chooserIntent,
                                PackageManager.MATCH_DEFAULT_ONLY
                            )

                        for (resolveInfo in resInfoList) {

                            grantUriPermission(
                                resolveInfo.activityInfo.packageName,
                                uri,
                                Intent.FLAG_GRANT_READ_URI_PERMISSION
                            )
                        }

                        startActivity(
                            chooserIntent
                        )

                        result.success(
                            true
                        )

                    } catch (e: Exception) {

                        Log.e(
                            TAG,
                            "❌ MA shareAiResponseRecording failed",
                            e
                        )

                        result.error(
                            "AI_RESPONSE_SHARE_ERROR",
                            e.message,
                            null
                        )
                    }
                }

                // ==================================================
                // DELETE ONE AI RESPONSE RECORDING
                // ==================================================

                "deleteAiResponseRecording" -> {

                    val filePath =
                        call.argument<String>("filePath")

                    Log.d(
                        TAG,
                        "🤖🗑 MA deleteAiResponseRecording path=$filePath"
                    )

                    if (filePath.isNullOrBlank()) {

                        result.error(
                            "INVALID_PATH",
                            "AI response file path is empty",
                            null
                        )

                        return@setMethodCallHandler
                    }

                    try {

                        val file =
                            File(filePath)

                        if (!isValidAiResponseFile(file)) {

                            result.error(
                                "INVALID_AI_RESPONSE_FILE",
                                "File is outside the AI response recording directory",
                                null
                            )

                            return@setMethodCallHandler
                        }

                        if (!file.exists()) {

                            result.success(
                                true
                            )

                            return@setMethodCallHandler
                        }

                        val deleted =
                            file.delete()

                        cleanupEmptyAiResponseDirectories()

                        Log.d(
                            TAG,
                            "🤖🗑 MA AI response deleted=$deleted"
                        )

                        result.success(
                            deleted
                        )

                    } catch (e: Exception) {

                        Log.e(
                            TAG,
                            "❌ MA deleteAiResponseRecording failed",
                            e
                        )

                        result.error(
                            "AI_RESPONSE_DELETE_ERROR",
                            e.message,
                            null
                        )
                    }
                }

                // ==================================================
                // CLEAR ALL AI RESPONSE RECORDINGS
                // ==================================================

                "clearAiResponseRecordings" -> {

                    Log.d(
                        TAG,
                        "🤖🧹 MA clearAiResponseRecordings()"
                    )

                    try {

                        val baseDir =
                            getAiResponseBaseDirectory()

                        var deletedCount =
                            0

                        if (baseDir.exists()) {

                            baseDir
                                .walkBottomUp()
                                .forEach { file ->

                                    if (
                                        file != baseDir &&
                                        file.isFile &&
                                        file.extension.equals(
                                            "wav",
                                            ignoreCase = true
                                        )
                                    ) {

                                        if (file.delete()) {
                                            deletedCount++
                                        }
                                    }
                                }

                            cleanupEmptyAiResponseDirectories()
                        }

                        Log.d(
                            TAG,
                            "🤖🧹 MA AI response files deleted=$deletedCount"
                        )

                        result.success(
                            true
                        )

                    } catch (e: Exception) {

                        Log.e(
                            TAG,
                            "❌ MA clearAiResponseRecordings failed",
                            e
                        )

                        result.error(
                            "AI_RESPONSE_CLEAR_ERROR",
                            e.message,
                            null
                        )
                    }
                }

                // ==================================================
                // MAKE CALL
                // ==================================================

                "makeNativeInternalCall" -> {

                    Log.d(
                        TAG,
                        "📞 MA makeNativeInternalCall()"
                    )

                    val number =
                        call.argument<String>("phoneNumber")

                    isAiModeActive =
                        call.argument<Boolean>("isAiMode")
                            ?: false

                    Log.d(
                        TAG,
                        "📞 MA Phone number = $number"
                    )

                    Log.d(
                        TAG,
                        "🤖 MA AI mode requested = $isAiModeActive"
                    )

                    if (number.isNullOrBlank()) {

                        Log.e(
                            TAG,
                            "❌ MA Phone number is empty"
                        )

                        result.error(
                            "INVALID_NUMBER",
                            "Phone number is empty",
                            null
                        )

                        return@setMethodCallHandler
                    }

                    /*
                     * CALL_PHONE permission
                     */

                    val callPermission =
                        ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.CALL_PHONE
                        )

                    Log.d(
                        TAG,
                        "📞 MA CALL_PHONE permission = $callPermission"
                    )

                    if (
                        callPermission !=
                        PackageManager.PERMISSION_GRANTED
                    ) {

                        Log.w(
                            TAG,
                            "⚠️ MA CALL_PHONE permission NOT GRANTED"
                        )

                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(
                                Manifest.permission.CALL_PHONE
                            ),
                            REQUEST_CALL_PHONE
                        )

                        result.error(
                            "CALL_PERMISSION",
                            "CALL_PHONE permission required",
                            null
                        )

                        return@setMethodCallHandler
                    }

                    Log.d(
                        TAG,
                        "✅ MA CALL_PHONE permission granted"
                    )

                    /*
                     * Configure audio
                     */

                    if (isAiModeActive) {

                        Log.d(
                            TAG,
                            "🤖 MA Applying AI audio mode BEFORE call"
                        )

                        applyAiAudioMode()

                    } else {

                        Log.d(
                            TAG,
                            "📞 MA Restoring normal audio BEFORE call"
                        )

                        restoreNormalAudio()
                    }

                    /*
                     * Place call
                     */

                    val success =
                        makeDirectTelecomCall(number)

                    Log.d(
                        TAG,
                        "📞 MA makeDirectTelecomCall result = $success"
                    )

                    result.success(success)
                }

                // ==================================================
                // SHARE WAV
                // ==================================================

                "shareRecordedChunk" -> {

                    Log.d(
                        TAG,
                        "📤 MA shareRecordedChunk()"
                    )

                    val filePath =
                        call.argument<String>("filePath")

                    Log.d(
                        TAG,
                        "📤 MA File path = $filePath"
                    )

                    if (filePath != null) {

                        val file = File(filePath)

                        Log.d(
                            TAG,
                            "📤 MA File exists = ${file.exists()}"
                        )

                        if (file.exists()) {

                            try {

                                val uri =
                                    FileProvider.getUriForFile(
                                        this,
                                        "$packageName.fileprovider",
                                        file
                                    )

                                Log.d(
                                    TAG,
                                    "📤 MA FileProvider URI = $uri"
                                )

                                val shareIntent =
                                    Intent(
                                        Intent.ACTION_SEND
                                    ).apply {

                                        type = "audio/x-wav"

                                        putExtra(
                                            Intent.EXTRA_STREAM,
                                            uri
                                        )

                                        putExtra(
                                            Intent.EXTRA_SUBJECT,
                                            "Call Recording"
                                        )

                                        addFlags(
                                            Intent.FLAG_GRANT_READ_URI_PERMISSION
                                        )
                                    }

                                val chooserIntent =
                                    Intent.createChooser(
                                        shareIntent,
                                        "Share WAV Recording"
                                    ).apply {

                                        addFlags(
                                            Intent.FLAG_GRANT_READ_URI_PERMISSION
                                        )
                                    }

                                val resInfoList =
                                    packageManager.queryIntentActivities(
                                        chooserIntent,
                                        PackageManager.MATCH_DEFAULT_ONLY
                                    )

                                Log.d(
                                    TAG,
                                    "📤 MA Share targets = ${resInfoList.size}"
                                )

                                for (resolveInfo in resInfoList) {

                                    val pkgName =
                                        resolveInfo
                                            .activityInfo
                                            .packageName

                                    Log.d(
                                        TAG,
                                        "📤 MA Granting URI permission to $pkgName"
                                    )

                                    grantUriPermission(
                                        pkgName,
                                        uri,
                                        Intent.FLAG_GRANT_READ_URI_PERMISSION
                                    )
                                }

                                startActivity(chooserIntent)

                                Log.d(
                                    TAG,
                                    "✅ MA Share chooser launched"
                                )

                                result.success(true)

                            } catch (e: Exception) {

                                Log.e(
                                    TAG,
                                    "❌ MA Share failed",
                                    e
                                )

                                result.error(
                                    "SHARE_ERROR",
                                    e.message,
                                    null
                                )
                            }

                        } else {

                            Log.e(
                                TAG,
                                "❌ MA WAV file does not exist"
                            )

                            result.error(
                                "FILE_NOT_FOUND",
                                "WAV file does not exist",
                                null
                            )
                        }

                    } else {

                        Log.e(
                            TAG,
                            "❌ MA filePath is null"
                        )

                        result.error(
                            "INVALID_PATH",
                            "File path is null",
                            null
                        )
                    }
                }

                // ==================================================
                // SET AUDIO MODE
                // ==================================================

                "setAudioMode" -> {

                    val aiMode =
                        call.argument<Boolean>("isAiMode")
                            ?: false

                    Log.d(
                        TAG,
                        "🔊 MA setAudioMode()"
                    )

                    Log.d(
                        TAG,
                        "🔊 MA Requested AI mode = $aiMode"
                    )

                    isAiModeActive = aiMode

                    if (aiMode) {

                        applyAiAudioMode()

                    } else {

                        restoreNormalAudio()
                    }

                    result.success(true)
                }

                // ==================================================
                // PLAY / INJECT AI AUDIO
                // ==================================================

                "playAiAudioChunk" -> {

                    Log.d(
                        TAG,
                        "================================================"
                    )

                    Log.d(
                        TAG,
                        "🤖 MA playAiAudioChunk() RECEIVED"
                    )

                    val pcmData =
                        call.argument<ByteArray>("pcmData")

                    val wavPath =
                        call.argument<String>("filePath")

                    Log.d(
                        TAG,
                        "🤖 MA PCM data present = ${pcmData != null}"
                    )

                    if (pcmData != null) {

                        Log.d(
                            TAG,
                            "🤖 MA PCM bytes = ${pcmData.size}"
                        )

                        if (pcmData.isNotEmpty()) {

                            Log.d(
                                TAG,
                                "🤖 MA PCM first bytes = ${
                                    pcmData
                                        .take(16)
                                        .joinToString(" ") {
                                            "%02X".format(it)
                                        }
                                }"
                            )
                        }
                    }

                    Log.d(
                        TAG,
                        "🤖 MA WAV path = $wavPath"
                    )

                    if (
                        pcmData == null &&
                        wavPath.isNullOrBlank()
                    ) {

                        Log.e(
                            TAG,
                            "❌ MA No PCM data or WAV path"
                        )

                        result.error(
                            "INVALID_AUDIO",
                            "PCM data or WAV path missing",
                            null
                        )

                        return@setMethodCallHandler
                    }

                    try {

                        val intent =
                            Intent(
                                "com.example.telicall_voice_app.INJECT_UPLINK_AUDIO"
                            ).apply {

                                setPackage(packageName)

                                putExtra(
                                    "pcm_data",
                                    pcmData
                                )

                                putExtra(
                                    "wav_path",
                                    wavPath
                                )
                            }

                        Log.d(
                            TAG,
                            "🤖 MA Sending INJECT_UPLINK_AUDIO broadcast"
                        )

                        Log.d(
                            TAG,
                            "🤖 MA Broadcast package = $packageName"
                        )

                        Log.d(
                            TAG,
                            "🤖 MA pcm_data bytes = ${pcmData?.size ?: 0}"
                        )

                        Log.d(
                            TAG,
                            "🤖 MA wav_path = $wavPath"
                        )

                        sendBroadcast(intent)

                        Log.d(
                            TAG,
                            "✅ MA INJECT_UPLINK_AUDIO broadcast SENT"
                        )

                        result.success(true)

                    } catch (e: Exception) {

                        Log.e(
                            TAG,
                            "❌ MA Failed to send AI audio broadcast",
                            e
                        )

                        result.error(
                            "INJECT_ERROR",
                            e.message,
                            null
                        )
                    }

                    Log.d(
                        TAG,
                        "================================================"
                    )
                }

                // ==================================================
                // DISCONNECT CALL
                // ==================================================

                "disconnectCall" -> {

                    Log.d(
                        TAG,
                        "🔴 MA disconnectCall()"
                    )

                    isAiModeActive = false

                    restoreNormalAudio()

                    val success =
                        hangUpActiveCall()

                    Log.d(
                        TAG,
                        "🔴 MA hangUpActiveCall result = $success"
                    )

                    result.success(success)
                }

                // ==================================================
                // CHECK DIALER
                // ==================================================

                "checkDialerStatus" -> {

                    Log.d(
                        TAG,
                        "☎️ MA checkDialerStatus()"
                    )

                    val isDialer =
                        checkDialerRole()

                    Log.d(
                        TAG,
                        "☎️ MA Is default dialer = $isDialer"
                    )

                    result.success(isDialer)
                }

                // ==================================================
                // REQUEST DIALER ROLE
                // ==================================================

                "requestDefaultDialerRole",
                "requestDialerRole" -> {

                    Log.d(
                        TAG,
                        "☎️ MA Requesting default dialer role"
                    )

                    requestDefaultDialerRole()

                    result.success(true)
                }

                // ==================================================
                // UNKNOWN METHOD
                // ==================================================

                else -> {

                    Log.w(
                        TAG,
                        "⚠️ MA Unknown Flutter method: ${call.method}"
                    )

                    result.notImplemented()
                }
            }

            Log.d(
                TAG,
                "📲 MA METHOD PROCESSING COMPLETE: ${call.method}"
            )

            Log.d(
                TAG,
                "================================================"
            )
        }
    }

    // ============================================================
    // START NEW CHUNK
    // ============================================================

    private fun startNewChunkFile() {

        Log.d(
            TAG,
            "🎙 MA startNewChunkFile()"
        )

        /*
         * Finalize previous chunk first
         */
        finalizeChunkFile()

        try {

            val recordDir =
                File(
                    getExternalFilesDir(null),
                    "recorded_chunks"
                )

            if (!recordDir.exists()) {

                val created =
                    recordDir.mkdirs()

                Log.d(
                    TAG,
                    "🎙 MA Recording directory created = $created"
                )
            }

            chunkIndex++

            totalChunksCreated++

            currentChunkFile =
                File(
                    recordDir,
                    "call_chunk_$chunkIndex.wav"
                )

            currentChunkOutputStream =
                FileOutputStream(
                    currentChunkFile
                )

            bytesRecordedInChunk = 0

            /*
             * Placeholder WAV header
             */
            currentChunkOutputStream?.write(
                ByteArray(44)
            )

            Log.d(
                TAG,
                "🎙 MA NEW CHUNK CREATED"
            )

            Log.d(
                TAG,
                "🎙 MA Chunk index = $chunkIndex"
            )

            Log.d(
                TAG,
                "🎙 MA Chunk file = ${currentChunkFile?.absolutePath}"
            )

            Log.d(
                TAG,
                "🎙 MA Max chunk bytes = $CHUNK_MAX_BYTES"
            )

        } catch (e: Exception) {

            Log.e(
                TAG,
                "❌ MA Failed to create chunk file",
                e
            )
        }
    }

    // ============================================================
    // WRITE PCM
    // ============================================================

    private fun writePcmToChunk(
        pcmBytes: ByteArray
    ) {

        try {

            if (pcmBytes.isEmpty()) {

                Log.w(
                    TAG,
                    "⚠️ MA writePcmToChunk received EMPTY PCM"
                )

                return
            }

            if (currentChunkOutputStream == null) {

                Log.w(
                    TAG,
                    "⚠️ MA No active chunk. Creating one."
                )

                startNewChunkFile()
            }

            currentChunkOutputStream?.write(
                pcmBytes
            )

            bytesRecordedInChunk +=
                pcmBytes.size

            totalPcmBytesRecorded +=
                pcmBytes.size

            /*
             * Log every PCM frame
             */
            Log.d(
                TAG,
                "🎙 MA PCM → WAV | " +
                    "frame=${pcmBytes.size} bytes | " +
                    "chunk=$bytesRecordedInChunk/$CHUNK_MAX_BYTES | " +
                    "total=$totalPcmBytesRecorded"
            )

            /*
             * Rotate chunk
             */
            if (
                bytesRecordedInChunk >=
                CHUNK_MAX_BYTES
            ) {

                Log.d(
                    TAG,
                    "🎙 MA Chunk reached maximum size"
                )

                startNewChunkFile()
            }

        } catch (e: Exception) {

            Log.e(
                TAG,
                "❌ MA Error writing PCM frame",
                e
            )
        }
    }

    // ============================================================
    // FINALIZE CHUNK
    // ============================================================

    private fun finalizeChunkFile() {

        try {

            if (currentChunkOutputStream == null) {

                Log.d(
                    TAG,
                    "🎙 MA finalizeChunkFile(): no active chunk"
                )

                return
            }

            Log.d(
                TAG,
                "🎙 MA Finalizing chunk..."
            )

            Log.d(
                TAG,
                "🎙 MA Chunk = ${currentChunkFile?.name}"
            )

            Log.d(
                TAG,
                "🎙 MA PCM bytes = $bytesRecordedInChunk"
            )

            currentChunkOutputStream?.flush()

            currentChunkOutputStream?.close()

            currentChunkOutputStream = null

            currentChunkFile?.let { file ->

                if (
                    file.exists() &&
                    bytesRecordedInChunk > 0
                ) {

                    writeWavHeader(
                        file,
                        bytesRecordedInChunk
                    )

                    Log.d(
                        TAG,
                        "================================================"
                    )

                    Log.d(
                        TAG,
                        "✅ MA WAV CHUNK SAVED"
                    )

                    Log.d(
                        TAG,
                        "✅ MA File = ${file.absolutePath}"
                    )

                    Log.d(
                        TAG,
                        "✅ MA Size = ${file.length()} bytes"
                    )

                    Log.d(
                        TAG,
                        "✅ MA PCM size = $bytesRecordedInChunk bytes"
                    )

                    Log.d(
                        TAG,
                        "================================================"
                    )

                    runOnUiThread {

                        try {

                            getMethodChannel()
                                ?.invokeMethod(
                                    "onNewChunkSaved",
                                    file.absolutePath
                                )

                            Log.d(
                                TAG,
                                "📱 MA Flutter callback sent: onNewChunkSaved"
                            )

                        } catch (e: Exception) {

                            Log.e(
                                TAG,
                                "❌ MA Flutter onNewChunkSaved failed",
                                e
                            )
                        }
                    }

                } else {

                    Log.w(
                        TAG,
                        "⚠️ MA Chunk empty or missing"
                    )

                    Log.w(
                        TAG,
                        "⚠️ MA Exists = ${file.exists()}"
                    )

                    Log.w(
                        TAG,
                        "⚠️ MA PCM bytes = $bytesRecordedInChunk"
                    )
                }
            }

            bytesRecordedInChunk = 0

        } catch (e: Exception) {

            Log.e(
                TAG,
                "❌ MA Error finalizing WAV chunk",
                e
            )
        }
    }

    // ============================================================
    // WAV HEADER
    // ============================================================

    private fun writeWavHeader(
        file: File,
        pcmDataLength: Int
    ) {

        Log.d(
            TAG,
            "🎵 MA Writing WAV header"
        )

        Log.d(
            TAG,
            "🎵 MA PCM length = $pcmDataLength"
        )

        val totalDataLen =
            pcmDataLength + 36

        val sampleRate = 16000

        val channels = 1

        val bitsPerSample = 16

        val byteRate =
            sampleRate *
                channels *
                bitsPerSample / 8

        val blockAlign =
            channels *
                bitsPerSample / 8

        val header =
            ByteArray(44)

        // RIFF
        header[0] = 'R'.code.toByte()
        header[1] = 'I'.code.toByte()
        header[2] = 'F'.code.toByte()
        header[3] = 'F'.code.toByte()

        header[4] =
            (totalDataLen and 0xff).toByte()

        header[5] =
            (totalDataLen shr 8 and 0xff).toByte()

        header[6] =
            (totalDataLen shr 16 and 0xff).toByte()

        header[7] =
            (totalDataLen shr 24 and 0xff).toByte()

        // WAVE
        header[8] = 'W'.code.toByte()
        header[9] = 'A'.code.toByte()
        header[10] = 'V'.code.toByte()
        header[11] = 'E'.code.toByte()

        // fmt
        header[12] = 'f'.code.toByte()
        header[13] = 'm'.code.toByte()
        header[14] = 't'.code.toByte()
        header[15] = ' '.code.toByte()

        // Subchunk1Size = 16
        header[16] = 16
        header[17] = 0
        header[18] = 0
        header[19] = 0

        // PCM format = 1
        header[20] = 1
        header[21] = 0

        // Channels
        header[22] =
            channels.toByte()

        header[23] = 0

        // Sample rate
        header[24] =
            (sampleRate and 0xff).toByte()

        header[25] =
            (sampleRate shr 8 and 0xff).toByte()

        header[26] =
            (sampleRate shr 16 and 0xff).toByte()

        header[27] =
            (sampleRate shr 24 and 0xff).toByte()

        // Byte rate
        header[28] =
            (byteRate and 0xff).toByte()

        header[29] =
            (byteRate shr 8 and 0xff).toByte()

        header[30] =
            (byteRate shr 16 and 0xff).toByte()

        header[31] =
            (byteRate shr 24 and 0xff).toByte()

        // Block align
        header[32] =
            blockAlign.toByte()

        header[33] = 0

        // Bits per sample
        header[34] =
            bitsPerSample.toByte()

        header[35] = 0

        // data
        header[36] = 'd'.code.toByte()
        header[37] = 'a'.code.toByte()
        header[38] = 't'.code.toByte()
        header[39] = 'a'.code.toByte()

        // PCM length
        header[40] =
            (pcmDataLength and 0xff).toByte()

        header[41] =
            (pcmDataLength shr 8 and 0xff).toByte()

        header[42] =
            (pcmDataLength shr 16 and 0xff).toByte()

        header[43] =
            (pcmDataLength shr 24 and 0xff).toByte()

        try {

            val raf =
                RandomAccessFile(
                    file,
                    "rw"
                )

            raf.seek(0)

            raf.write(header)

            raf.close()

            Log.d(
                TAG,
                "✅ MA WAV header written"
            )

            Log.d(
                TAG,
                "🎵 MA SampleRate = $sampleRate"
            )

            Log.d(
                TAG,
                "🎵 MA Channels = $channels"
            )

            Log.d(
                TAG,
                "🎵 MA Bits = $bitsPerSample"
            )

            Log.d(
                TAG,
                "🎵 MA ByteRate = $byteRate"
            )

            Log.d(
                TAG,
                "🎵 MA BlockAlign = $blockAlign"
            )

        } catch (e: Exception) {

            Log.e(
                TAG,
                "❌ MA Failed writing WAV header",
                e
            )
        }
    }

    // ============================================================
    // AI RESPONSE RECORDING FILE HELPERS
    // ============================================================

    private fun getAiResponseBaseDirectory(): File {

        return File(
            getExternalFilesDir(null),
            "ai_response_audio"
        )
    }


    private fun getAiResponseRecordingFiles(): List<File> {

        val baseDir =
            getAiResponseBaseDirectory()

        if (!baseDir.exists()) {

            return emptyList()
        }

        return baseDir
            .walkTopDown()
            .filter { file ->

                file.isFile &&
                    file.extension.equals(
                        "wav",
                        ignoreCase = true
                    )
            }
            .sortedByDescending { file ->

                file.lastModified()
            }
            .toList()
    }


    private fun isValidAiResponseFile(
        file: File
    ): Boolean {

        return try {

            val basePath =
                getAiResponseBaseDirectory()
                    .canonicalFile
                    .toPath()

            val filePath =
                file
                    .canonicalFile
                    .toPath()

            filePath.startsWith(
                basePath
            )

        } catch (e: Exception) {

            Log.e(
                TAG,
                "❌ MA AI response path validation failed",
                e
            )

            false
        }
    }


    private fun cleanupEmptyAiResponseDirectories() {

        try {

            val baseDir =
                getAiResponseBaseDirectory()

            if (!baseDir.exists()) {

                return
            }

            baseDir
                .walkBottomUp()
                .filter { file ->

                    file.isDirectory &&
                        file != baseDir
                }
                .forEach { directory ->

                    val children =
                        directory.listFiles()

                    if (
                        children == null ||
                        children.isEmpty()
                    ) {

                        directory.delete()
                    }
                }

        } catch (e: Exception) {

            Log.w(
                TAG,
                "⚠️ MA Could not clean empty AI response directories",
                e
            )
        }
    }


    // ============================================================
    // CHECK DIALER ROLE
    // ============================================================

    private fun checkDialerRole(): Boolean {

        Log.d(
            TAG,
            "☎️ MA Checking default dialer role"
        )

        return try {

            if (
                Build.VERSION.SDK_INT >=
                Build.VERSION_CODES.Q
            ) {

                val roleManager =
                    getSystemService(
                        Context.ROLE_SERVICE
                    ) as RoleManager

                val available =
                    roleManager.isRoleAvailable(
                        RoleManager.ROLE_DIALER
                    )

                val held =
                    roleManager.isRoleHeld(
                        RoleManager.ROLE_DIALER
                    )

                Log.d(
                    TAG,
                    "☎️ MA Dialer role available = $available"
                )

                Log.d(
                    TAG,
                    "☎️ MA Dialer role held = $held"
                )

                held

            } else {

                val telecom =
                    getSystemService(
                        Context.TELECOM_SERVICE
                    ) as TelecomManager

                val defaultDialer =
                    telecom.defaultDialerPackage

                Log.d(
                    TAG,
                    "☎️ MA Default dialer = $defaultDialer"
                )

                packageName ==
                    defaultDialer
            }

        } catch (e: Exception) {

            Log.e(
                TAG,
                "❌ MA checkDialerRole failed",
                e
            )

            false
        }
    }

    // ============================================================
    // REQUEST DIALER ROLE
    // ============================================================

    private fun requestDefaultDialerRole() {

        Log.d(
            TAG,
            "☎️ MA requestDefaultDialerRole()"
        )

        try {

            if (
                Build.VERSION.SDK_INT >=
                Build.VERSION_CODES.Q
            ) {

                val roleManager =
                    getSystemService(
                        Context.ROLE_SERVICE
                    ) as RoleManager

                val available =
                    roleManager.isRoleAvailable(
                        RoleManager.ROLE_DIALER
                    )

                val held =
                    roleManager.isRoleHeld(
                        RoleManager.ROLE_DIALER
                    )

                Log.d(
                    TAG,
                    "☎️ MA ROLE_DIALER available = $available"
                )

                Log.d(
                    TAG,
                    "☎️ MA ROLE_DIALER held = $held"
                )

                if (
                    available &&
                    !held
                ) {

                    Log.d(
                        TAG,
                        "☎️ MA Opening dialer-role request"
                    )

                    val intent =
                        roleManager.createRequestRoleIntent(
                            RoleManager.ROLE_DIALER
                        )

                    startActivityForResult(
                        intent,
                        5001
                    )

                } else {

                    Log.d(
                        TAG,
                        "☎️ MA Dialer role request not required"
                    )
                }

            } else {

                Log.d(
                    TAG,
                    "☎️ MA Opening default-app settings"
                )

                try {

                    val intent =
                        Intent(
                            Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS
                        )

                    startActivity(intent)

                } catch (e: Exception) {

                    Log.e(
                        TAG,
                        "❌ MA Failed opening default apps",
                        e
                    )
                }
            }

        } catch (e: Exception) {

            Log.e(
                TAG,
                "❌ MA requestDefaultDialerRole failed",
                e
            )
        }
    }

    // ============================================================
    // PLACE CALL
    // ============================================================

    private fun makeDirectTelecomCall(
        number: String
    ): Boolean {

        Log.d(
            TAG,
            "================================================"
        )

        Log.d(
            TAG,
            "📞 MA makeDirectTelecomCall()"
        )

        Log.d(
            TAG,
            "📞 MA Original number = $number"
        )

        var cleanNumber =
            number.replace(
                "[^0-9+]".toRegex(),
                ""
            )

        Log.d(
            TAG,
            "📞 MA Clean number = $cleanNumber"
        )

        if (
            cleanNumber.length == 10 &&
            !cleanNumber.startsWith("+")
        ) {

            cleanNumber =
                "+91$cleanNumber"

            Log.d(
                TAG,
                "🇮🇳 MA Added India country code"
            )
        }

        Log.d(
            TAG,
            "📞 MA Final number = $cleanNumber"
        )

        val uri =
            Uri.parse(
                "tel:$cleanNumber"
            )

        Log.d(
            TAG,
            "📞 MA Telecom URI = $uri"
        )

        return try {

            val telecom =
                getSystemService(
                    Context.TELECOM_SERVICE
                ) as TelecomManager

            Log.d(
                TAG,
                "📞 MA TelecomManager obtained"
            )

            val extras =
                Bundle()

            /*
             * Get SIM accounts
             */

            val accounts =
                telecom.callCapablePhoneAccounts

            Log.d(
                TAG,
                "📞 MA Call-capable accounts = ${accounts?.size ?: 0}"
            )

            if (
                accounts != null &&
                accounts.isNotEmpty()
            ) {

                val account =
                    accounts[0]

                extras.putParcelable(
                    TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE,
                    account
                )

                Log.d(
                    TAG,
                    "📱 MA Using PhoneAccount = $account"
                )

            } else {

                Log.w(
                    TAG,
                    "⚠️ MA No call-capable PhoneAccount found"
                )

                val selected =
                    telecom
                        .getUserSelectedOutgoingPhoneAccount()

                Log.d(
                    TAG,
                    "📱 MA User selected account = $selected"
                )

                if (selected != null) {

                    extras.putParcelable(
                        TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE,
                        selected
                    )
                }
            }

            /*
             * Speakerphone
             */

            extras.putBoolean(
                TelecomManager.EXTRA_START_CALL_WITH_SPEAKERPHONE,
                false
            )

            Log.d(
                TAG,
                "📞 MA Speakerphone start = false"
            )

            /*
             * Place call
             */

            Log.d(
                TAG,
                "📞 MA Calling TelecomManager.placeCall()"
            )

            telecom.placeCall(
                uri,
                extras
            )

            Log.d(
                TAG,
                "================================================"
            )

            Log.d(
                TAG,
                "✅ MA TELECOM CALL PLACED"
            )

            Log.d(
                TAG,
                "📞 MA Number = $cleanNumber"
            )

            Log.d(
                TAG,
                "================================================"
            )

            true

        } catch (e: Exception) {

            Log.e(
                TAG,
                "❌ MA Telecom placeCall FAILED",
                e
            )

            false
        }
    }

    // ============================================================
    // HANG UP
    // ============================================================

    private fun hangUpActiveCall(): Boolean {

        Log.d(
            TAG,
            "🔴 MA hangUpActiveCall()"
        )

        return try {

            val telecom =
                getSystemService(
                    Context.TELECOM_SERVICE
                ) as TelecomManager

            if (
                Build.VERSION.SDK_INT >=
                Build.VERSION_CODES.P
            ) {

                val permission =
                    ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.ANSWER_PHONE_CALLS
                    )

                Log.d(
                    TAG,
                    "🔴 MA ANSWER_PHONE_CALLS permission = $permission"
                )

                if (
                    permission !=
                    PackageManager.PERMISSION_GRANTED
                ) {

                    Log.w(
                        TAG,
                        "⚠️ MA ANSWER_PHONE_CALLS not granted"
                    )

                    ActivityCompat.requestPermissions(
                        this,
                        arrayOf(
                            Manifest.permission.ANSWER_PHONE_CALLS
                        ),
                        REQUEST_ANSWER_PHONE
                    )

                    return false
                }
            }

            Log.d(
                TAG,
                "🔴 MA Calling TelecomManager.endCall()"
            )

            telecom.endCall()

            Log.d(
                TAG,
                "✅ MA Telecom call ended"
            )

            true

        } catch (e: Exception) {

            Log.e(
                TAG,
                "❌ MA End call failed",
                e
            )

            false
        }
    }

    // ============================================================
    // AI AUDIO MODE
    // ============================================================

    private fun applyAiAudioMode() {

        Log.d(
            TAG,
            "================================================"
        )

        Log.d(
            TAG,
            "🤖 MA applyAiAudioMode()"
        )

        try {

            val audio =
                getSystemService(
                    Context.AUDIO_SERVICE
                ) as AudioManager

            Log.d(
                TAG,
                "🔊 MA Previous audio mode = ${audio.mode}"
            )

            Log.d(
                TAG,
                "🔊 MA Previous speakerphone = ${audio.isSpeakerphoneOn}"
            )

            Log.d(
                TAG,
                "🔊 MA Previous microphone mute = ${audio.isMicrophoneMute}"
            )

            audio.mode =
                AudioManager.MODE_IN_CALL

            audio.isSpeakerphoneOn =
                false

            /*
             * IMPORTANT:
             * We leave microphone unmuted here because
             * your native audio pipeline may depend on
             * the telecom audio path.
             */
            audio.isMicrophoneMute =
                false

            val maxVolume =
                audio.getStreamMaxVolume(
                    AudioManager.STREAM_VOICE_CALL
                )

            audio.setStreamVolume(
                AudioManager.STREAM_VOICE_CALL,
                maxVolume,
                0
            )

            Log.d(
                TAG,
                "🤖 MA AI AUDIO MODE ENABLED"
            )

            Log.d(
                TAG,
                "🔊 MA Audio mode = ${audio.mode}"
            )

            Log.d(
                TAG,
                "🔊 MA Speakerphone = ${audio.isSpeakerphoneOn}"
            )

            Log.d(
                TAG,
                "🔊 MA Mic mute = ${audio.isMicrophoneMute}"
            )

            Log.d(
                TAG,
                "🔊 MA Voice-call volume = ${audio.getStreamVolume(AudioManager.STREAM_VOICE_CALL)}/$maxVolume"
            )

        } catch (e: Exception) {

            Log.e(
                TAG,
                "❌ MA AI audio mode error",
                e
            )
        }

        Log.d(
            TAG,
            "================================================"
        )
    }

    // ============================================================
    // NORMAL AUDIO
    // ============================================================

    private fun restoreNormalAudio() {

        Log.d(
            TAG,
            "================================================"
        )

        Log.d(
            TAG,
            "🔊 MA restoreNormalAudio()"
        )

        try {

            val audio =
                getSystemService(
                    Context.AUDIO_SERVICE
                ) as AudioManager

            Log.d(
                TAG,
                "🔊 MA Current audio mode = ${audio.mode}"
            )

            audio.mode =
                AudioManager.MODE_IN_CALL

            audio.isMicrophoneMute =
                false

            val maxVolume =
                audio.getStreamMaxVolume(
                    AudioManager.STREAM_VOICE_CALL
                )

            val targetVolume =
                maxVolume / 2

            audio.setStreamVolume(
                AudioManager.STREAM_VOICE_CALL,
                targetVolume,
                0
            )

            Log.d(
                TAG,
                "🔊 MA NORMAL AUDIO RESTORED"
            )

            Log.d(
                TAG,
                "🔊 MA Audio mode = ${audio.mode}"
            )

            Log.d(
                TAG,
                "🔊 MA Mic mute = ${audio.isMicrophoneMute}"
            )

            Log.d(
                TAG,
                "🔊 MA Voice-call volume = ${audio.getStreamVolume(AudioManager.STREAM_VOICE_CALL)}/$maxVolume"
            )

        } catch (e: Exception) {

            Log.e(
                TAG,
                "❌ MA Restore audio error",
                e
            )
        }

        Log.d(
            TAG,
            "================================================"
        )
    }

    // ============================================================
    // ACTIVITY RESULT
    // ============================================================

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ) {

        super.onActivityResult(
            requestCode,
            resultCode,
            data
        )

        Log.d(
            TAG,
            "📱 MA onActivityResult()"
        )

        Log.d(
            TAG,
            "📱 MA requestCode = $requestCode"
        )

        Log.d(
            TAG,
            "📱 MA resultCode = $resultCode"
        )

        if (requestCode == 5001) {

            Log.d(
                TAG,
                "☎️ MA Dialer role activity returned"
            )

            val isDialer =
                checkDialerRole()

            Log.d(
                TAG,
                "☎️ MA Dialer role result = $isDialer"
            )

            getMethodChannel()?.invokeMethod(
                "dialerRoleChanged",
                isDialer
            )

            Log.d(
                TAG,
                "📱 MA Flutter dialerRoleChanged callback sent"
            )
        }
    }

    // ============================================================
    // PERMISSION RESULT
    // ============================================================

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {

        super.onRequestPermissionsResult(
            requestCode,
            permissions,
            grantResults
        )

        Log.d(
            TAG,
            "================================================"
        )

        Log.d(
            TAG,
            "🔐 MA Permission result"
        )

        Log.d(
            TAG,
            "🔐 MA Request code = $requestCode"
        )

        permissions.forEachIndexed { index, permission ->

            val granted =
                grantResults.getOrNull(index) ==
                    PackageManager.PERMISSION_GRANTED

            Log.d(
                TAG,
                "🔐 MA $permission = $granted"
            )
        }

        Log.d(
            TAG,
            "================================================"
        )
    }

    // ============================================================
    // DESTROY
    // ============================================================

    override fun onDestroy() {

        Log.d(
            TAG,
            "================================================"
        )

        Log.d(
            TAG,
            "📱 MA MainActivity onDestroy()"
        )

        try {

            callStateReceiver?.let {

                unregisterReceiver(it)

                Log.d(
                    TAG,
                    "📡 MA BroadcastReceiver unregistered"
                )
            }

        } catch (e: Exception) {

            Log.e(
                TAG,
                "⚠️ MA Receiver unregister error",
                e
            )
        }

        /*
         * Important:
         *
         * AppInCallService may still exist while
         * MainActivity is destroyed.
         *
         * Setting this to null means the service
         * cannot send callbacks through this channel.
         */
        _methodChannel = null

        Log.d(
            TAG,
            "📱 MA MethodChannel cleared"
        )

        Log.d(
            TAG,
            "📱 MA MainActivity destroyed"
        )

        Log.d(
            TAG,
            "================================================"
        )

        super.onDestroy()
    }
}