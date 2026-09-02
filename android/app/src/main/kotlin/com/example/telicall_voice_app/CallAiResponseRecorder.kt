package com.example.telicall_voice_app

import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.util.concurrent.atomic.AtomicBoolean


/**
 * ================================================================
 * CallAiResponseRecorder
 * ================================================================
 *
 * PURPOSE:
 *
 * Saves the EXACT AI/TTS PCM audio that is sent to the customer.
 *
 * IMPORTANT:
 *
 * This class DOES NOT use:
 *
 * - AudioRecord
 * - MIC
 * - VOICE_DOWNLINK
 * - VOICE_UPLINK
 * - VOICE_CALL
 *
 * It simply receives the AI PCM bytes that are already being sent
 * to CallAudioInjector and saves those same bytes as WAV.
 *
 *
 * Expected architecture:
 *
 * Python TTS
 *      ↓
 * Flutter / WebSocket
 *      ↓
 * Android receives AI PCM
 *      ↓
 * ┌───────────────────────────────┐
 * │ Same PCM                     │
 * │                               │
 * ├──> CallAudioInjector          │
 * │       ↓                       │
 * │    Customer                   │
 * │                               │
 * └──> CallAiResponseRecorder     │
 *         ↓                       │
 *    ai_response_001.wav          │
 * └───────────────────────────────┘
 *
 */
class CallAiResponseRecorder(
    private val listener: Listener
) {

    companion object {

        private const val TAG =
            "CallAiResponseRecorder"


        // ============================================================
        // AUDIO FORMAT
        // ============================================================

        /**
         * Must match the PCM format sent by backend/TTS.
         */
        private const val SAMPLE_RATE =
            16000

        private const val CHANNELS =
            1

        private const val BITS_PER_SAMPLE =
            16

        private const val BYTES_PER_SAMPLE =
            2


        /**
         * 16000 samples/sec
         * x 1 channel
         * x 2 bytes/sample
         *
         * = 32000 bytes per second
         */
        private const val BYTE_RATE =
            SAMPLE_RATE *
                    CHANNELS *
                    BYTES_PER_SAMPLE
    }


    // ================================================================
    // LISTENER
    // ================================================================

    interface Listener {

        /**
         * Called when a new AI response recording begins.
         */
        fun onAiResponseRecordingStarted(
            responseNumber: Int,
            filePath: String
        )


        /**
         * Called after a complete AI response WAV
         * has been successfully finalized.
         */
        fun onAiResponseCreated(
            filePath: String,
            responseNumber: Int,
            durationMs: Long,
            audioBytes: Long
        )


        /**
         * Called when current AI response is stopped.
         */
        fun onAiResponseRecordingStopped()


        /**
         * Called if recorder encounters an error.
         */
        fun onError(
            error: String
        )
    }


    // ================================================================
    // SESSION STATE
    // ================================================================

    private val sessionStarted =
        AtomicBoolean(false)


    private val responseRecording =
        AtomicBoolean(false)


    private val lock =
        Any()


    // ================================================================
    // DIRECTORY
    // ================================================================

    private var sessionDirectory:
            File? = null


    // ================================================================
    // CURRENT RESPONSE FILE
    // ================================================================

    private var currentFile:
            File? = null


    private var currentOutput:
            FileOutputStream? = null


    private var currentResponseNumber =
        0


    private var currentAudioBytes =
        0L


    private var currentResponseStartTime =
        0L


    // ================================================================
    // ALL SAVED RESPONSES
    // ================================================================

    private val recordedFiles =
        mutableListOf<String>()


    // ================================================================
    // START SESSION
    // ================================================================

    /**
     * Start one AI response recording session.
     *
     * Usually call this when the phone call becomes ACTIVE.
     *
     * Example:
     *
     * val directory = File(
     *     getExternalFilesDir(null),
     *     "ai_response_audio"
     * )
     *
     * aiResponseRecorder.startSession(directory)
     */
    fun startSession(
        baseDirectory: File
    ): Boolean {

        synchronized(lock) {

            if (
                sessionStarted.get()
            ) {

                Log.w(
                    TAG,
                    "⚠️ AI response session already active"
                )

                return true
            }


            try {

                if (
                    !baseDirectory.exists()
                ) {

                    if (
                        !baseDirectory.mkdirs() &&
                        !baseDirectory.exists()
                    ) {

                        notifyError(
                            "Could not create AI response base directory"
                        )

                        return false
                    }
                }


                // ====================================================
                // CREATE UNIQUE DIRECTORY FOR THIS CALL
                // ====================================================

                val directoryName =
                    "ai_call_${System.currentTimeMillis()}"


                sessionDirectory =
                    File(
                        baseDirectory,
                        directoryName
                    )


                if (
                    !sessionDirectory!!.exists()
                ) {

                    val created =
                        sessionDirectory!!.mkdirs()


                    if (
                        !created &&
                        !sessionDirectory!!.exists()
                    ) {

                        notifyError(
                            "Could not create AI response session directory"
                        )

                        return false
                    }
                }


                // ====================================================
                // RESET SESSION
                // ====================================================

                currentResponseNumber =
                    0


                recordedFiles.clear()


                sessionStarted.set(
                    true
                )


                Log.i(
                    TAG,
                    "======================================"
                )

                Log.i(
                    TAG,
                    "🤖 AI RESPONSE RECORDING SESSION STARTED"
                )

                Log.i(
                    TAG,
                    "🎚 PCM = 16kHz / Mono / PCM16"
                )

                Log.i(
                    TAG,
                    "📁 ${sessionDirectory!!.absolutePath}"
                )

                Log.i(
                    TAG,
                    "======================================"
                )


                return true


            } catch (
                e: Exception
            ) {

                Log.e(
                    TAG,
                    "❌ Failed to start AI response session",
                    e
                )


                notifyError(
                    e.message
                        ?: "AI response session start failed"
                )


                return false
            }
        }
    }


    // ================================================================
    // START ONE AI RESPONSE
    // ================================================================

    /**
     * Call this BEFORE sending the first PCM chunk
     * of one AI response.
     *
     * One call to startResponse()
     * =
     * one WAV file.
     */
    fun startResponse():
            Boolean {

        synchronized(lock) {

            if (
                !sessionStarted.get()
            ) {

                notifyError(
                    "AI response session has not been started"
                )

                return false
            }


            // ========================================================
            // FINISH PREVIOUS RESPONSE IF STILL OPEN
            // ========================================================

            if (
                responseRecording.get()
            ) {

                Log.w(
                    TAG,
                    "⚠️ Previous AI response still open. Finalizing it."
                )


                finishResponse()
            }


            try {

                currentResponseNumber++


                val filename =
                    String.format(
                        "ai_response_%03d.wav",
                        currentResponseNumber
                    )


                val file =
                    File(
                        sessionDirectory,
                        filename
                    )


                currentFile =
                    file


                currentOutput =
                    FileOutputStream(
                        file
                    )


                // ====================================================
                // WAV HEADER PLACEHOLDER
                // ====================================================

                currentOutput!!.write(
                    ByteArray(
                        44
                    )
                )


                currentAudioBytes =
                    0L


                currentResponseStartTime =
                    System.currentTimeMillis()


                responseRecording.set(
                    true
                )


                Log.i(
                    TAG,
                    "--------------------------------------"
                )

                Log.i(
                    TAG,
                    "🤖 AI RESPONSE STARTED #$currentResponseNumber"
                )

                Log.i(
                    TAG,
                    "📄 $filename"
                )

                Log.i(
                    TAG,
                    "--------------------------------------"
                )


                listener.onAiResponseRecordingStarted(
                    currentResponseNumber,
                    file.absolutePath
                )


                return true


            } catch (
                e: Exception
            ) {

                Log.e(
                    TAG,
                    "❌ Could not create AI response file",
                    e
                )


                notifyError(
                    e.message
                        ?: "Could not create AI response audio file"
                )


                cleanupCurrentResponse()


                return false
            }
        }
    }


    // ================================================================
    // APPEND AI PCM
    // ================================================================

    /**
     * THIS IS THE MOST IMPORTANT METHOD.
     *
     * Send the EXACT PCM bytes that you also send
     * to CallAudioInjector.
     *
     *
     * Example:
     *
     * aiResponseRecorder.appendPcm(aiPcm)
     *
     * audioInjector.inject(aiPcm)
     *
     *
     * Expected format:
     *
     * PCM SIGNED 16-BIT
     * LITTLE ENDIAN
     * MONO
     * 16000 Hz
     */
    fun appendPcm(
        pcmData: ByteArray
    ): Boolean {

        return appendPcm(
            pcmData,
            0,
            pcmData.size
        )
    }


    /**
     * Offset/length version.
     */
    fun appendPcm(
        pcmData: ByteArray,
        offset: Int,
        length: Int
    ): Boolean {

        synchronized(lock) {

            if (
                !sessionStarted.get()
            ) {

                Log.w(
                    TAG,
                    "⚠️ PCM ignored: session not active"
                )

                return false
            }


            if (
                !responseRecording.get()
            ) {

                Log.w(
                    TAG,
                    "⚠️ PCM ignored: no AI response currently open"
                )

                return false
            }


            if (
                length <= 0
            ) {

                return false
            }


            if (
                offset < 0 ||
                offset + length > pcmData.size
            ) {

                notifyError(
                    "Invalid PCM offset/length"
                )

                return false
            }


            try {

                currentOutput?.write(
                    pcmData,
                    offset,
                    length
                )


                currentAudioBytes +=
                    length.toLong()


                // ====================================================
                // DEBUG LOG
                // ====================================================

                if (
                    currentAudioBytes %
                    32000L <
                    length
                ) {

                    Log.d(
                        TAG,
                        "🤖 AI PCM | " +
                                "response=$currentResponseNumber " +
                                "| bytes=$currentAudioBytes " +
                                "| duration≈${calculateDurationMs(currentAudioBytes)}ms"
                    )
                }


                return true


            } catch (
                e: Exception
            ) {

                Log.e(
                    TAG,
                    "❌ Failed writing AI PCM",
                    e
                )


                notifyError(
                    e.message
                        ?: "AI PCM write failed"
                )


                return false
            }
        }
    }


    // ================================================================
    // FINISH ONE AI RESPONSE
    // ================================================================

    /**
     * Call when the COMPLETE AI response has finished
     * being sent to CallAudioInjector.
     *
     * Returns saved WAV path.
     */
    fun finishResponse():
            String? {

        synchronized(lock) {

            if (
                !responseRecording.get()
            ) {

                return null
            }


            val output =
                currentOutput


            val file =
                currentFile


            val responseNumber =
                currentResponseNumber


            val audioLength =
                currentAudioBytes


            responseRecording.set(
                false
            )


            try {

                // ====================================================
                // CLOSE PCM STREAM
                // ====================================================

                output?.flush()

                output?.close()


                currentOutput =
                    null


                if (
                    file == null
                ) {

                    return null
                }


                // ====================================================
                // DELETE EMPTY AI RESPONSES
                // ====================================================

                if (
                    audioLength <=
                    0
                ) {

                    Log.w(
                        TAG,
                        "⚠️ Empty AI response deleted: ${file.name}"
                    )


                    file.delete()


                    currentFile =
                        null


                    currentAudioBytes =
                        0


                    return null
                }


                // ====================================================
                // FINALIZE WAV HEADER
                // ====================================================

                writeWavHeader(
                    file,
                    audioLength
                )


                val durationMs =
                    calculateDurationMs(
                        audioLength
                    )


                recordedFiles.add(
                    file.absolutePath
                )


                Log.i(
                    TAG,
                    "======================================"
                )

                Log.i(
                    TAG,
                    "💾 AI RESPONSE SAVED"
                )

                Log.i(
                    TAG,
                    "🤖 Response #$responseNumber"
                )

                Log.i(
                    TAG,
                    "📄 ${file.name}"
                )

                Log.i(
                    TAG,
                    "🎵 Audio bytes=$audioLength"
                )

                Log.i(
                    TAG,
                    "⏱ Duration=${durationMs}ms"
                )

                Log.i(
                    TAG,
                    "📁 ${file.absolutePath}"
                )

                Log.i(
                    TAG,
                    "======================================"
                )


                listener.onAiResponseCreated(
                    file.absolutePath,
                    responseNumber,
                    durationMs,
                    audioLength
                )


                listener.onAiResponseRecordingStopped()


                val result =
                    file.absolutePath


                currentFile =
                    null


                currentAudioBytes =
                    0


                currentResponseStartTime =
                    0L


                return result


            } catch (
                e: Exception
            ) {

                Log.e(
                    TAG,
                    "❌ Failed finalizing AI response",
                    e
                )


                notifyError(
                    e.message
                        ?: "Failed finalizing AI response"
                )


                cleanupCurrentResponse()


                return null
            }
        }
    }


    // ================================================================
    // CANCEL RESPONSE
    // ================================================================

    /**
     * Use this if TTS generation fails or the AI response
     * should NOT be kept.
     */
    fun cancelResponse() {

        synchronized(lock) {

            Log.w(
                TAG,
                "⚠️ Cancelling AI response #$currentResponseNumber"
            )


            responseRecording.set(
                false
            )


            try {

                currentOutput?.flush()

            } catch (
                _: Exception
            ) {
            }


            try {

                currentOutput?.close()

            } catch (
                _: Exception
            ) {
            }


            currentOutput =
                null


            try {

                currentFile?.delete()

            } catch (
                _: Exception
            ) {
            }


            currentFile =
                null


            currentAudioBytes =
                0L


            currentResponseStartTime =
                0L


            listener.onAiResponseRecordingStopped()
        }
    }


    // ================================================================
    // STOP COMPLETE SESSION
    // ================================================================

    /**
     * Usually call this when the cellular call disconnects.
     */
    fun stopSession() {

        synchronized(lock) {

            if (
                !sessionStarted.get()
            ) {

                return
            }


            Log.i(
                TAG,
                "🛑 STOPPING AI RESPONSE SESSION"
            )


            // ========================================================
            // FINALIZE CURRENT RESPONSE
            // ========================================================

            if (
                responseRecording.get()
            ) {

                finishResponse()
            }


            sessionStarted.set(
                false
            )


            Log.i(
                TAG,
                "✅ AI RESPONSE SESSION STOPPED"
            )


            Log.i(
                TAG,
                "📊 Responses saved=${recordedFiles.size}"
            )
        }
    }


    // ================================================================
    // WAV HEADER
    // ================================================================

    /**
     * Writes standard:
     *
     * PCM
     * Mono
     * 16 kHz
     * 16-bit
     */
    private fun writeWavHeader(
        file: File,
        audioDataLength: Long
    ) {

        try {

            val totalDataLength =
                audioDataLength +
                        36L


            val byteRate =
                SAMPLE_RATE *
                        CHANNELS *
                        BYTES_PER_SAMPLE


            val blockAlign =
                CHANNELS *
                        BYTES_PER_SAMPLE


            RandomAccessFile(
                file,
                "rw"
            ).use { raf ->

                raf.seek(
                    0
                )


                // ====================================================
                // RIFF
                // ====================================================

                raf.writeBytes(
                    "RIFF"
                )


                writeLittleEndianInt(
                    raf,
                    totalDataLength.toInt()
                )


                // ====================================================
                // WAVE
                // ====================================================

                raf.writeBytes(
                    "WAVE"
                )


                // ====================================================
                // fmt
                // ====================================================

                raf.writeBytes(
                    "fmt "
                )


                // fmt chunk size
                writeLittleEndianInt(
                    raf,
                    16
                )


                // Audio format = PCM
                writeLittleEndianShort(
                    raf,
                    1
                )


                // Channels
                writeLittleEndianShort(
                    raf,
                    CHANNELS
                )


                // Sample rate
                writeLittleEndianInt(
                    raf,
                    SAMPLE_RATE
                )


                // Byte rate
                writeLittleEndianInt(
                    raf,
                    byteRate
                )


                // Block align
                writeLittleEndianShort(
                    raf,
                    blockAlign
                )


                // Bits per sample
                writeLittleEndianShort(
                    raf,
                    BITS_PER_SAMPLE
                )


                // ====================================================
                // DATA
                // ====================================================

                raf.writeBytes(
                    "data"
                )


                writeLittleEndianInt(
                    raf,
                    audioDataLength.toInt()
                )
            }


        } catch (
            e: Exception
        ) {

            Log.e(
                TAG,
                "❌ WAV header creation failed",
                e
            )


            throw e
        }
    }


    // ================================================================
    // LITTLE ENDIAN INT
    // ================================================================

    private fun writeLittleEndianInt(
        raf: RandomAccessFile,
        value: Int
    ) {

        raf.write(
            value and
                    0xFF
        )


        raf.write(
            value shr 8 and
                    0xFF
        )


        raf.write(
            value shr 16 and
                    0xFF
        )


        raf.write(
            value shr 24 and
                    0xFF
        )
    }


    // ================================================================
    // LITTLE ENDIAN SHORT
    // ================================================================

    private fun writeLittleEndianShort(
        raf: RandomAccessFile,
        value: Int
    ) {

        raf.write(
            value and
                    0xFF
        )


        raf.write(
            value shr 8 and
                    0xFF
        )
    }


    // ================================================================
    // DURATION
    // ================================================================

    private fun calculateDurationMs(
        audioBytes: Long
    ): Long {

        if (
            BYTE_RATE <=
            0
        ) {

            return 0L
        }


        return (
                audioBytes *
                        1000L
                ) /
                BYTE_RATE
    }


    // ================================================================
    // CLEANUP
    // ================================================================

    private fun cleanupCurrentResponse() {

        try {

            currentOutput?.close()

        } catch (
            _: Exception
        ) {
        }


        currentOutput =
            null


        responseRecording.set(
            false
        )


        currentFile =
            null


        currentAudioBytes =
            0L


        currentResponseStartTime =
            0L
    }


    // ================================================================
    // ERROR
    // ================================================================

    private fun notifyError(
        error: String
    ) {

        Log.e(
            TAG,
            "❌ $error"
        )


        listener.onError(
            error
        )
    }


    // ================================================================
    // GETTERS
    // ================================================================

    fun isSessionActive():
            Boolean {

        return sessionStarted.get()
    }


    fun isResponseRecording():
            Boolean {

        return responseRecording.get()
    }


    fun getRecordedFiles():
            List<String> {

        synchronized(lock) {

            return recordedFiles
                .toList()
        }
    }


    fun getSessionDirectory():
            String? {

        return sessionDirectory
            ?.absolutePath
    }


    fun getCurrentResponseNumber():
            Int {

        return currentResponseNumber
    }


    fun getCurrentAudioBytes():
            Long {

        return currentAudioBytes
    }
}