package com.example.telicall_voice_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.telecom.Call
import android.telecom.InCallService
import android.util.Log
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs
import kotlin.math.max

class AppInCallService : InCallService() {

    companion object {
        private const val TAG = "AppInCallService"

        const val ACTION_PCM_FRAME =
            "com.example.telicall_voice_app.PCM_DOWNLINK_FRAME"
            
        const val ACTION_CALL_DISCONNECTED =
            "com.example.telicall_voice_app.CALL_DISCONNECTED"

        private const val SAMPLE_RATE = 16000

        private const val CHANNEL_CONFIG =
            AudioFormat.CHANNEL_IN_MONO

        private const val AUDIO_FORMAT =
            AudioFormat.ENCODING_PCM_16BIT
    }

    private var currentCall: Call? = null
    private var callCallback: Call.Callback? = null

    private var audioRecord: AudioRecord? = null
    private var audioExecutor: ExecutorService? = null
    private val audioRunning = AtomicBoolean(false)
    private val mainHandler = Handler(Looper.getMainLooper())

    // System Audio & AI Management
    private var audioManager: AudioManager? = null
    private val audioInjector = CallAudioInjector()

    // WAV Storage Trackers
    private var wavFile: File? = null
    private var wavOutput: FileOutputStream? = null
    private var wavDataSize: Long = 0
    private val sessionChunkFiles = mutableListOf<File>()

    // Broadcast Listener for AI Mode
    private val aiModeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val enable = intent?.getBooleanExtra("enable_ai", false) ?: false
            if (enable) {
                enableAiMode()
            } else {
                disableAiMode()
            }
        }
    }

    private val audioInjectionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.example.telicall_voice_app.INJECT_UPLINK_AUDIO") {
                val pcmData = intent.getByteArrayExtra("pcm_data")
                if (pcmData != null && audioRunning.get()) {
                    audioExecutor?.execute {
                        Log.d(TAG, "🔊 Injecting AI PCM into call...")
                        audioInjector.writePcmData(pcmData)
                    }
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "================================")
        Log.i(TAG, "🚀 AppInCallService CREATED")
        Log.i(TAG, "Package = $packageName")
        Log.i(TAG, "================================")

        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        try {
            registerReceiver(
                aiModeReceiver,
                IntentFilter("com.example.telicall_voice_app.TOGGLE_AI_MODE")
            )
            registerReceiver(
                audioInjectionReceiver,
                IntentFilter("com.example.telicall_voice_app.INJECT_UPLINK_AUDIO")
            )
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to register receivers", e)
        }
    }

    override fun onCallAdded(call: Call) {
        super.onCallAdded(call)
        currentCall = call

        Log.i(TAG, "📞 onCallAdded() | State = ${call.state}")
        logCallState(call.state)

        callCallback = object : Call.Callback() {
            override fun onStateChanged(call: Call, state: Int) {
                Log.i(TAG, "📱 CALL STATE CHANGED = $state")
                logCallState(state)

                when (state) {
                    Call.STATE_ACTIVE -> {
                        Log.i(TAG, "🟢 CALL ACTIVE")
                        startAudioCapture()
                    }
                    Call.STATE_DISCONNECTING, Call.STATE_DISCONNECTED -> {
                        Log.i(TAG, "🔴 CALL DISCONNECTING / DISCONNECTED - Immediately halting audio")
                        handleCallHangup()
                    }
                }
            }
        }

        call.registerCallback(callCallback!!)

        if (call.state == Call.STATE_ACTIVE) {
            Log.i(TAG, "🟢 Call already ACTIVE")
            startAudioCapture()
        }
    }

    private fun handleCallHangup() {
        // Stop capture immediately to prevent recording local mic on fallback
        stopAudioCapture()
        audioInjector.stop()
        disableAiMode()

        // Inform WebSocket component to close session immediately
        sendBroadcast(Intent(ACTION_CALL_DISCONNECTED))
    }

    override fun onCallRemoved(call: Call) {
        Log.i(TAG, "🔴 onCallRemoved()")
        if (call == currentCall) {
            handleCallHangup()
            finalizeSessionRecording()

            callCallback?.let {
                try {
                    call.unregisterCallback(it)
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Failed to unregister callback", e)
                }
            }
            callCallback = null
            currentCall = null
        }
        super.onCallRemoved(call)
    }

    private fun logCallState(state: Int) {
        when (state) {
            Call.STATE_NEW -> Log.i(TAG, "📱 CALL STATE = NEW")
            Call.STATE_CONNECTING -> Log.i(TAG, "📱 CALL STATE = CONNECTING")
            Call.STATE_DIALING -> Log.i(TAG, "📱 CALL STATE = DIALING")
            Call.STATE_RINGING -> Log.i(TAG, "📱 CALL STATE = RINGING")
            Call.STATE_ACTIVE -> Log.i(TAG, "📱 CALL STATE = ACTIVE")
            Call.STATE_HOLDING -> Log.i(TAG, "📱 CALL STATE = HOLDING")
            Call.STATE_DISCONNECTED -> Log.i(TAG, "📱 CALL STATE = DISCONNECTED")
            Call.STATE_DISCONNECTING -> Log.i(TAG, "📱 CALL STATE = DISCONNECTING")
            else -> Log.i(TAG, "📱 CALL STATE = UNKNOWN($state)")
        }
    }

    // ============================================================
    // AI MODE AUDIO CONTROLS
    // ============================================================

    fun enableAiMode() {
        try {
            audioManager?.let { am ->
                am.isMicrophoneMute = true
                am.isSpeakerphoneOn = false
                am.setStreamVolume(AudioManager.STREAM_VOICE_CALL, 0, 0)
                Log.i(TAG, "🤖 AI Mode ENABLED: Mic muted & live call audio silenced locally.")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to enable AI Mode mute", e)
        }
    }

    fun disableAiMode() {
        try {
            audioManager?.let { am ->
                am.isMicrophoneMute = false
                am.isSpeakerphoneOn = false

                val maxVolume = am.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)
                am.setStreamVolume(AudioManager.STREAM_VOICE_CALL, (maxVolume * 0.7).toInt(), 0)
                Log.i(TAG, "👤 AI Mode DISABLED: Mic & speaker restored")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to disable AI Mode mute", e)
        }
    }

    // ============================================================
    // START AUDIO CAPTURE (STRICT VOICE_DOWNLINK / COMM)
    // ============================================================

    private fun startAudioCapture() {
        if (audioRunning.get()) {
            Log.i(TAG, "🎙 Audio capture already running")
            return
        }

        Log.i(TAG, "🎙 Starting audio pipeline")

        val minBuffer = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            CHANNEL_CONFIG,
            AUDIO_FORMAT
        )

        if (minBuffer <= 0) {
            Log.e(TAG, "❌ Invalid AudioRecord buffer size: $minBuffer")
            return
        }

        val bufferSize = max(minBuffer * 2, 4096)

        try {
            startWavRecording()

            // Strictly restrict sources to downlink/communications to avoid capturing raw MIC
            val preferredSources = intArrayOf(
                MediaRecorder.AudioSource.VOICE_COMMUNICATION, // 7 (Hardware optimized comms)
                MediaRecorder.AudioSource.MIC,                 // 1 (Standard microphone input)
                MediaRecorder.AudioSource.VOICE_DOWNLINK       // 3 (Incoming caller's voice exclusively - as a last resort)
            )

            var initializedRecord: AudioRecord? = null

            for (source in preferredSources) {
                try {
                    Log.i(TAG, "🔄 Attempting AudioRecord with AudioSource: $source")
                    val rec = AudioRecord(
                        source,
                        SAMPLE_RATE,
                        CHANNEL_CONFIG,
                        AUDIO_FORMAT,
                        bufferSize
                    )

                    if (rec.state == AudioRecord.STATE_INITIALIZED) {
                        initializedRecord = rec
                        Log.i(TAG, "✅ AudioRecord initialized successfully with AudioSource: $source")
                        break
                    } else {
                        rec.release()
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "⚠️ Failed source $source: ${e.message}")
                }
            }

            audioRecord = initializedRecord

            if (audioRecord == null || audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                Log.e(TAG, "❌ AudioRecord failed to initialize across designated sources")
                audioRecord?.release()
                audioRecord = null
                stopWavRecording()
                return
            }

            audioRunning.set(true)
            audioInjector.start()
            audioRecord?.startRecording()

            audioExecutor = Executors.newSingleThreadExecutor()
            audioExecutor?.execute {
                audioCaptureLoop(bufferSize)
            }

            Log.i(TAG, "🎙 Audio capture thread launched successfully")

        } catch (e: Exception) {
            Log.e(TAG, "❌ AudioRecord start failed", e)
            stopAudioCapture()
        }
    }

    private fun calculateMaxAmplitude(pcm: ByteArray): Int {
        var maxAmplitude = 0
        var i = 0
        while (i + 1 < pcm.size) {
            val low = pcm[i].toInt() and 0xFF
            val high = pcm[i + 1].toInt()
            val sample = (high shl 8) or low
            val amplitude = abs(sample.toShort().toInt())

            if (amplitude > maxAmplitude) {
                maxAmplitude = amplitude
            }
            i += 2
        }
        return maxAmplitude
    }

    // ============================================================
    // AUDIO RECORD LOOP
    // ============================================================

    private fun audioCaptureLoop(bufferSize: Int) {
        val buffer = ByteArray(2048)
        var readCount = 0

        Log.i(TAG, "🎙 Audio Capture Loop Active")

        while (audioRunning.get()) {
            val count = audioRecord?.read(buffer, 0, buffer.size) ?: -1

            if (count > 0 && audioRunning.get()) {
                readCount++
                val pcm = buffer.copyOf(count)

                writeWavData(pcm)

                if (readCount % 50 == 0) {
                    val maxAmp = calculateMaxAmplitude(pcm)
                    Log.d(TAG, "🎙 Frame #$readCount ($count bytes) | Max Amp: $maxAmp")
                }

                // Send PCM data directly to Flutter via MethodChannel on the main thread
                mainHandler.post {
                    MainActivity.getMethodChannel()
                        ?.invokeMethod("onCallerAudioReceived", pcm)
                }
            } else {
                try {
                    Thread.sleep(10)
                } catch (_: InterruptedException) {
                    break
                }
            }
        }

        Log.i(TAG, "🎙 Audio capture loop terminated cleanly")
    }

    // ============================================================
    // WAV FILE HANDLING & MERGING LOGIC
    // ============================================================

    private fun startWavRecording() {
        try {
            val directory = File(filesDir, "call_recordings")
            if (!directory.exists()) {
                directory.mkdirs()
            }

            val filename = "chunk_${System.currentTimeMillis()}.wav"
            wavFile = File(directory, filename)
            wavOutput = FileOutputStream(wavFile)
            wavDataSize = 0

            wavOutput?.write(ByteArray(44))
            wavFile?.let { sessionChunkFiles.add(it) }
            Log.i(TAG, "💾 WAV chunk initialized: ${wavFile?.absolutePath}")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to create WAV file", e)
        }
    }

    private fun writeWavData(pcm: ByteArray) {
        try {
            wavOutput?.write(pcm)
            wavDataSize += pcm.size
        } catch (e: Exception) {
            Log.e(TAG, "❌ WAV write failed", e)
        }
    }

    private fun stopWavRecording() {
        val file = wavFile ?: return
        val output = wavOutput ?: return

        try {
            output.flush()
            output.close()
            wavOutput = null

            RandomAccessFile(file, "rw").use { raf ->
                raf.seek(0)
                raf.writeBytes("RIFF")
                raf.writeInt(Integer.reverseBytes((36 + wavDataSize).toInt()))
                raf.writeBytes("WAVE")
                raf.writeBytes("fmt ")
                raf.writeInt(Integer.reverseBytes(16))
                raf.writeShort(java.lang.Short.reverseBytes(1.toShort()).toInt())
                raf.writeShort(java.lang.Short.reverseBytes(1.toShort()).toInt())
                raf.writeInt(Integer.reverseBytes(SAMPLE_RATE))
                raf.writeInt(Integer.reverseBytes(SAMPLE_RATE * 2))
                raf.writeShort(java.lang.Short.reverseBytes(2.toShort()).toInt())
                raf.writeShort(java.lang.Short.reverseBytes(16.toShort()).toInt())
                raf.writeBytes("data")
                raf.writeInt(Integer.reverseBytes(wavDataSize.toInt()))
            }

            Log.i(TAG, "💾 Chunk Saved cleanly: ${file.absolutePath} ($wavDataSize bytes)")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to finalize WAV header", e)
        } finally {
            wavFile = null
            wavOutput = null
            wavDataSize = 0
        }
    }

    private fun finalizeSessionRecording() {
        if (sessionChunkFiles.isEmpty()) return

        val directory = File(filesDir, "call_recordings")
        val finalFile = File(directory, "call_recording_${System.currentTimeMillis()}.wav")

        if (sessionChunkFiles.size == 1) {
            val singleChunk = sessionChunkFiles[0]
            if (singleChunk.exists()) {
                singleChunk.renameTo(finalFile)
                Log.i(TAG, "💾 Single session recording finalized: ${finalFile.absolutePath}")
            }
        } else {
            mergeWavFiles(sessionChunkFiles, finalFile)
        }

        sessionChunkFiles.clear()
    }

    private fun mergeWavFiles(inputFiles: List<File>, outputFile: File) {
        var totalAudioLen: Long = 0
        inputFiles.forEach { file ->
            if (file.exists() && file.length() > 44) {
                totalAudioLen += (file.length() - 44)
            }
        }

        val totalDataLen = totalAudioLen + 36
        val byteRate = (SAMPLE_RATE * 1 * 2).toLong()

        try {
            val out = FileOutputStream(outputFile)

            val header = ByteArray(44)
            header[0] = 'R'.code.toByte(); header[1] = 'I'.code.toByte()
            header[2] = 'F'.code.toByte(); header[3] = 'F'.code.toByte()

            header[4] = (totalDataLen and 0xFFL).toByte()
            header[5] = ((totalDataLen shr 8) and 0xFFL).toByte()
            header[6] = ((totalDataLen shr 16) and 0xFFL).toByte()
            header[7] = ((totalDataLen shr 24) and 0xFFL).toByte()

            header[8] = 'W'.code.toByte(); header[9] = 'A'.code.toByte()
            header[10] = 'V'.code.toByte(); header[11] = 'E'.code.toByte()
            header[12] = 'f'.code.toByte(); header[13] = 'm'.code.toByte()
            header[14] = 't'.code.toByte(); header[15] = ' '.code.toByte()

            header[16] = 16; header[17] = 0; header[18] = 0; header[19] = 0
            header[20] = 1; header[21] = 0 // PCM
            header[22] = 1; header[23] = 0 // Mono

            header[24] = (SAMPLE_RATE and 0xFF).toByte()
            header[25] = ((SAMPLE_RATE shr 8) and 0xFF).toByte()
            header[26] = ((SAMPLE_RATE shr 16) and 0xFF).toByte()
            header[27] = ((SAMPLE_RATE shr 24) and 0xFF).toByte()

            header[28] = (byteRate and 0xFFL).toByte()
            header[29] = ((byteRate shr 8) and 0xFFL).toByte()
            header[30] = ((byteRate shr 16) and 0xFFL).toByte()
            header[31] = ((byteRate shr 24) and 0xFFL).toByte()

            header[32] = 2; header[33] = 0
            header[34] = 16; header[35] = 0

            header[36] = 'd'.code.toByte(); header[37] = 'a'.code.toByte()
            header[38] = 't'.code.toByte(); header[39] = 'a'.code.toByte()

            header[40] = (totalAudioLen and 0xFFL).toByte()
            header[41] = ((totalAudioLen shr 8) and 0xFFL).toByte()
            header[42] = ((totalAudioLen shr 16) and 0xFFL).toByte()
            header[43] = ((totalAudioLen shr 24) and 0xFFL).toByte()

            out.write(header, 0, 44)

            val buffer = ByteArray(2048)
            for (file in inputFiles) {
                if (!file.exists() || file.length() <= 44) continue
                val inputStream = FileInputStream(file)
                inputStream.skip(44)

                var bytesRead: Int
                while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                    out.write(buffer, 0, bytesRead)
                }
                inputStream.close()
            }

            out.close()

            inputFiles.forEach { file -> if (file.exists()) file.delete() }
            Log.i(TAG, "💾 Successfully merged ${inputFiles.size} chunks into single file: ${outputFile.absolutePath}")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to merge WAV chunk files", e)
        }
    }

    private fun stopAudioCapture() {
        if (!audioRunning.getAndSet(false)) {
            stopWavRecording()
            return
        }

        Log.i(TAG, "🛑 Stopping audio capture immediately")

        try {
            audioRecord?.apply {
                if (recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                    stop()
                }
                release()
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ AudioRecord release error", e)
        }
        audioRecord = null

        try {
            audioExecutor?.shutdownNow()
        } catch (e: Exception) {
            Log.e(TAG, "❌ Executor shutdown error", e)
        }
        audioExecutor = null

        stopWavRecording()
        Log.i(TAG, "🛑 Audio capture stopped completely")
    }

    override fun onDestroy() {
        Log.i(TAG, "🛑 AppInCallService DESTROYED")
        try {
            unregisterReceiver(audioInjectionReceiver)
            unregisterReceiver(aiModeReceiver)
        } catch (_: Exception) {}
        
        stopAudioCapture()
        finalizeSessionRecording()
        disableAiMode()
        super.onDestroy()
    }
}