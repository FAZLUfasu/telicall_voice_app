package com.example.telicall_voice_app

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.sqrt

class CallAudioRecorder(
    private val listener: Listener
) {

    companion object {
        private const val TAG = "CallAudioRecorder"

        private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT

        // Chunk duration: 3 seconds per file
        private const val CHUNK_DURATION_MS = 3000L
    }

    interface Listener {
        fun onRecordingStarted(directory: String)
        fun onChunkCreated(
            filePath: String,
            chunkNumber: Int,
            rms: Float,
            peak: Float
        )
        fun onRecordingStopped()
        fun onError(error: String)
    }

    private var audioRecord: AudioRecord? = null
    private var recordingThread: Thread? = null

    @Volatile
    private var isRecording = false

    private var selectedSampleRate = 16000
    private var selectedAudioSource = MediaRecorder.AudioSource.VOICE_CALL

    private var callDirectory: File? = null
    private var currentOutput: FileOutputStream? = null
    private var currentFile: File? = null

    private var chunkNumber = 0
    private var currentChunkStartTime = 0L
    private var bytesWrittenForChunk = 0

    private val recordedFiles = mutableListOf<String>()

    // ============================================================
    // START RECORDING
    // ============================================================

    fun start(baseDirectory: File): Boolean {
        if (isRecording) {
            Log.w(TAG, "⚠️ Recorder already running")
            return false
        }

        try {
            // ----------------------------------------------------
            // Create unique directory for this call
            // ----------------------------------------------------
            val callName = "call_${System.currentTimeMillis()}"
            callDirectory = File(baseDirectory, callName)

            if (!callDirectory!!.exists()) {
                val created = callDirectory!!.mkdirs()
                if (!created) {
                    notifyError("Could not create recording directory")
                    return false
                }
            }

            // ----------------------------------------------------
            // Initialize AudioRecord with Fallback Strategy
            // ----------------------------------------------------
            var initializedRecord: AudioRecord? = null
            val sampleRates = intArrayOf(16000, 8000)
            val audioSources = intArrayOf(
                MediaRecorder.AudioSource.VOICE_CALL,      // 4
                MediaRecorder.AudioSource.VOICE_DOWNLINK,  // 3
                MediaRecorder.AudioSource.VOICE_UPLINK,    // 2
                MediaRecorder.AudioSource.VOICE_COMMUNICATION, // 7
                MediaRecorder.AudioSource.MIC              // 1
            )

            sourceLoop@ for (rate in sampleRates) {
                for (source in audioSources) {
                    val minBuf = AudioRecord.getMinBufferSize(rate, CHANNEL_CONFIG, AUDIO_FORMAT)
                    if (minBuf <= 0) continue

                    val bufSize = max(minBuf * 2, rate * 2)

                    try {
                        val rec = AudioRecord(
                            source,
                            rate,
                            CHANNEL_CONFIG,
                            AUDIO_FORMAT,
                            bufSize
                        )

                        if (rec.state == AudioRecord.STATE_INITIALIZED) {
                            initializedRecord = rec
                            selectedSampleRate = rate
                            selectedAudioSource = source
                            Log.i(TAG, "✅ AudioRecord Initialized | Source: $source | Rate: $rate Hz")
                            break@sourceLoop
                        } else {
                            rec.release()
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "⚠️ Failed source $source at rate $rate: ${e.message}")
                    }
                }
            }

            audioRecord = initializedRecord

            if (audioRecord == null || audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                notifyError("AudioRecord failed to initialize across all configurations")
                audioRecord?.release()
                audioRecord = null
                return false
            }

            // ----------------------------------------------------
            // Start Capture
            // ----------------------------------------------------
            isRecording = true
            audioRecord?.startRecording()

            Log.i(TAG, "================================")
            Log.i(TAG, "🎙 AUDIO RECORDING STARTED")
            Log.i(TAG, "📡 Sample Rate: $selectedSampleRate Hz")
            Log.i(TAG, "🎯 Audio Source: $selectedAudioSource")
            Log.i(TAG, "📁 Directory: ${callDirectory!!.absolutePath}")
            Log.i(TAG, "================================")

            listener.onRecordingStarted(callDirectory!!.absolutePath)

            // ----------------------------------------------------
            // Launch Recording Thread
            // ----------------------------------------------------
            recordingThread = Thread(
                { recordLoop() },
                "CallAudioRecorderThread"
            )
            recordingThread?.start()

            return true

        } catch (e: SecurityException) {
            Log.e(TAG, "❌ RECORD_AUDIO permission denied", e)
            notifyError("RECORD_AUDIO permission denied")
            return false
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to start recorder", e)
            notifyError(e.message ?: "Unknown recorder error")
            return false
        }
    }

    // ============================================================
    // RECORDING LOOP
    // ============================================================

    private fun recordLoop() {
        val buffer = ByteArray(2048)

        try {
            createNewChunk()

            while (isRecording) {
                val bytesRead = audioRecord?.read(buffer, 0, buffer.size) ?: -1

                if (bytesRead <= 0) {
                    if (bytesRead < 0) {
                        Log.w(TAG, "⚠️ AudioRecord read error = $bytesRead")
                    }
                    continue
                }

                // ------------------------------------------------
                // Calculate Levels
                // ------------------------------------------------
                val rms = calculateRms(buffer, bytesRead)
                val peak = calculatePeak(buffer, bytesRead)

                // ------------------------------------------------
                // Write Raw PCM Data
                // ------------------------------------------------
                currentOutput?.write(buffer, 0, bytesRead)
                bytesWrittenForChunk += bytesRead

                // ------------------------------------------------
                // Diagnostic Output
                // ------------------------------------------------
                if (bytesWrittenForChunk % 16000 < bytesRead) {
                    Log.d(TAG, "🎙 AUDIO BUFFER bytes=$bytesRead | rms=$rms | peak=$peak")
                }

                // ------------------------------------------------
                // Check Chunk Duration
                // ------------------------------------------------
                val elapsed = System.currentTimeMillis() - currentChunkStartTime
                if (elapsed >= CHUNK_DURATION_MS) {
                    closeCurrentChunk(rms, peak)
                    if (isRecording) {
                        createNewChunk()
                    }
                }
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ Recording loop error", e)
            notifyError(e.message ?: "Recording loop error")
        } finally {
            try {
                closeCurrentChunk(0f, 0f)
            } catch (_: Exception) {
            }
            Log.i(TAG, "🎙 Audio capture loop stopped")
        }
    }

    // ============================================================
    // CREATE NEW AUDIO CHUNK
    // ============================================================

    private fun createNewChunk() {
        try {
            chunkNumber++
            val filename = String.format("audio_%03d.wav", chunkNumber)
            val file = File(callDirectory, filename)

            currentFile = file
            currentOutput = FileOutputStream(file)

            // Reserve 44-byte WAV header space
            currentOutput!!.write(ByteArray(44))

            bytesWrittenForChunk = 0
            currentChunkStartTime = System.currentTimeMillis()

            recordedFiles.add(file.absolutePath)
            Log.i(TAG, "🎙 NEW AUDIO CHUNK: $filename")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Could not create audio chunk", e)
            notifyError(e.message ?: "Could not create audio chunk")
        }
    }

    // ============================================================
    // CLOSE CURRENT CHUNK
    // ============================================================

    private fun closeCurrentChunk(rms: Float, peak: Float) {
        val output = currentOutput ?: return
        val file = currentFile ?: return

        try {
            output.flush()
            output.close()
            currentOutput = null

            // Write updated WAV header to start of file
            writeWavHeader(file, bytesWrittenForChunk)

            Log.i(TAG, "💾 AUDIO CHUNK SAVED: ${file.name} (${file.length()} bytes)")

            listener.onChunkCreated(
                file.absolutePath,
                chunkNumber,
                rms,
                peak
            )
        } catch (e: Exception) {
            Log.e(TAG, "❌ Could not close audio chunk", e)
        }
    }

    // ============================================================
    // WAV HEADER WRITER
    // ============================================================

    private fun writeWavHeader(file: File, audioDataLength: Int) {
        try {
            val totalDataLength = audioDataLength + 36
            val byteRate = selectedSampleRate * 2

            RandomAccessFile(file, "rw").use { raf ->
                raf.seek(0)
                raf.writeBytes("RIFF")
                raf.writeInt(Integer.reverseBytes(totalDataLength))
                raf.writeBytes("WAVE")
                raf.writeBytes("fmt ")
                raf.writeInt(Integer.reverseBytes(16)) // Subchunk1Size
                raf.writeShort(java.lang.Short.reverseBytes(1.toShort()).toInt()) // PCM = 1
                raf.writeShort(java.lang.Short.reverseBytes(1.toShort()).toInt()) // Mono = 1
                raf.writeInt(Integer.reverseBytes(selectedSampleRate))
                raf.writeInt(Integer.reverseBytes(byteRate))
                raf.writeShort(java.lang.Short.reverseBytes(2.toShort()).toInt()) // BlockAlign
                raf.writeShort(java.lang.Short.reverseBytes(16.toShort()).toInt()) // BitsPerSample
                raf.writeBytes("data")
                raf.writeInt(Integer.reverseBytes(audioDataLength))
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to write WAV header", e)
        }
    }

    // ============================================================
    // RMS & PEAK CALCULATIONS
    // ============================================================

    private fun calculateRms(buffer: ByteArray, length: Int): Float {
        var sum = 0.0
        val samples = length / 2
        if (samples == 0) return 0f

        var i = 0
        while (i < length - 1) {
            val low = buffer[i].toInt() and 0xFF
            val high = buffer[i + 1].toInt()
            val sample = (high shl 8) or low
            val signedSample = sample.toShort().toDouble()

            sum += signedSample * signedSample
            i += 2
        }

        return (sqrt(sum / samples) / 32768.0).toFloat()
    }

    private fun calculatePeak(buffer: ByteArray, length: Int): Float {
        var peak = 0
        var i = 0
        while (i < length - 1) {
            val low = buffer[i].toInt() and 0xFF
            val high = buffer[i + 1].toInt()
            val sample = (high shl 8) or low
            val absolute = abs(sample.toShort().toInt())

            if (absolute > peak) {
                peak = absolute
            }
            i += 2
        }

        return peak / 32768f
    }

    // ============================================================
    // STOP RECORDING
    // ============================================================

    fun stop() {
        if (!isRecording) return

        Log.i(TAG, "🛑 STOPPING AUDIO RECORDER")
        isRecording = false

        try {
            audioRecord?.stop()
        } catch (e: Exception) {
            Log.e(TAG, "⚠️ Error stopping AudioRecord", e)
        }

        try {
            audioRecord?.release()
        } catch (_: Exception) {
        }
        audioRecord = null

        try {
            recordingThread?.join(1000)
        } catch (_: InterruptedException) {
        }
        recordingThread = null

        Log.i(TAG, "🎙 AUDIO RECORDING STOPPED")
        listener.onRecordingStopped()
    }

    // ============================================================
    // ERROR & GETTERS
    // ============================================================

    private fun notifyError(error: String) {
        Log.e(TAG, "❌ $error")
        listener.onError(error)
    }

    fun getRecordedFiles(): List<String> = recordedFiles.toList()

    fun getCallDirectory(): String? = callDirectory?.absolutePath

    fun isCurrentlyRecording(): Boolean = isRecording
}