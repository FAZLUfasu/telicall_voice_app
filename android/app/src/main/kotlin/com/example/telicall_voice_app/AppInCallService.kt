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
import kotlin.math.sqrt


class AppInCallService : InCallService() {

    companion object {

        private const val TAG = "AppInCallService"

        // ============================================================
        // FLUTTER / APP ACTIONS
        // ============================================================

        /**
         * CUSTOMER / REMOTE CALLER PCM
         *
         * This must contain ONLY VOICE_DOWNLINK audio.
         */
        const val ACTION_PCM_FRAME =
            "com.example.telicall_voice_app.PCM_DOWNLINK_FRAME"

        const val ACTION_CALL_DISCONNECTED =
            "com.example.telicall_voice_app.CALL_DISCONNECTED"

        /**
         * AI-generated PCM which should be injected into uplink.
         */
        const val ACTION_INJECT_UPLINK_AUDIO =
            "com.example.telicall_voice_app.INJECT_UPLINK_AUDIO"

        private const val ACTION_TOGGLE_AI_MODE =
            "com.example.telicall_voice_app.TOGGLE_AI_MODE"


        // ============================================================
        // AUDIO CONFIGURATION
        // ============================================================

        private const val SAMPLE_RATE = 16000

        private const val CHANNEL_CONFIG =
            AudioFormat.CHANNEL_IN_MONO

        private const val AUDIO_FORMAT =
            AudioFormat.ENCODING_PCM_16BIT


        /**
         * IMPORTANT:
         *
         * VOICE_DOWNLINK = CUSTOMER → PHONE
         *
         * DO NOT add:
         *
         * MIC
         * VOICE_COMMUNICATION
         * VOICE_RECOGNITION
         *
         * because these may capture the local user instead.
         */
        private val DOWNLINK_SOURCES = intArrayOf(
            MediaRecorder.AudioSource.VOICE_DOWNLINK
        )


        /**
         * IMPORTANT DEBUG SWITCH
         *
         * KEEP FALSE while testing customer/downlink capture.
         *
         * When customer RX is proven to work,
         * change to true to start AI injection automatically.
         */
        private const val ENABLE_AI_INJECTOR_DURING_RX_TEST = false


        /**
         * Logging interval.
         *
         * Every 5 AudioRecord reads.
         */
        private const val AUDIO_DEBUG_INTERVAL = 5
    }


    // ================================================================
    // CALL STATE
    // ================================================================

    private var currentCall: Call? = null

    private var callCallback: Call.Callback? = null

    private val callEnded =
        AtomicBoolean(false)

    private val hangupHandled =
        AtomicBoolean(false)


    // ================================================================
    // AUDIO CAPTURE
    // ================================================================

    private var audioRecord: AudioRecord? = null

    private var audioExecutor: ExecutorService? = null

    private val audioRunning =
        AtomicBoolean(false)

    private val mainHandler =
        Handler(Looper.getMainLooper())


    // ================================================================
    // AUDIO MANAGER
    // ================================================================

    private var audioManager: AudioManager? = null


    // ================================================================
    // AI AUDIO INJECTOR
    // ================================================================

    private val audioInjector =
        CallAudioInjector()

    private val injectorStarted =
        AtomicBoolean(false)


    // ================================================================
    // AI RESPONSE RECORDER
    // ================================================================

    private lateinit var aiResponseRecorder:
        CallAiResponseRecorder


    // ================================================================
    // WAV STORAGE
    // ================================================================

    private var wavFile: File? = null

    private var wavOutput: FileOutputStream? = null

    private var wavDataSize: Long = 0

    private var chunkIndex = 0

    private val sessionChunkFiles =
        mutableListOf<File>()


    // ================================================================
    // AUDIO STATISTICS
    // ================================================================

    private data class AudioStats(
        val peak: Int,
        val rms: Double,
        val nonZeroSamples: Int,
        val totalSamples: Int
    )


    // ================================================================
    // AI MODE RECEIVER
    // ================================================================

    private val aiModeReceiver =
        object : BroadcastReceiver() {

            override fun onReceive(
                context: Context?,
                intent: Intent?
            ) {

                if (callEnded.get()) {

                    Log.w(
                        TAG,
                        "🤖 Ignoring AI mode request because call ended"
                    )

                    return
                }


                val enable =
                    intent?.getBooleanExtra(
                        "enable_ai",
                        false
                    ) ?: false


                if (enable) {

                    enableAiMode()

                } else {

                    disableAiMode()
                }
            }
        }


    // ================================================================
    // AI AUDIO INJECTION RECEIVER
    // ================================================================

    private val audioInjectionReceiver =
        object : BroadcastReceiver() {

            override fun onReceive(
                context: Context?,
                intent: Intent?
            ) {

                if (
                    intent?.action !=
                    ACTION_INJECT_UPLINK_AUDIO
                ) {
                    return
                }


                if (callEnded.get()) {

                    Log.w(
                        TAG,
                        "🔇 Ignoring AI PCM because call ended"
                    )

                    return
                }


                if (!audioRunning.get()) {

                    Log.w(
                        TAG,
                        "🔇 Ignoring AI PCM because audio pipeline is stopped"
                    )

                    return
                }


                val pcmData =
                    intent.getByteArrayExtra(
                        "pcm_data"
                    )


                if (
                    pcmData == null ||
                    pcmData.isEmpty()
                ) {

                    Log.w(
                        TAG,
                        "⚠️ Received empty AI PCM"
                    )

                    return
                }


                val pcmCopy =
                    pcmData.copyOf()


                audioExecutor?.execute {

                    if (
                        callEnded.get() ||
                        !audioRunning.get()
                    ) {

                        return@execute
                    }


                    try {

                        ensureAudioInjectorStarted()


                        Log.d(
                            TAG,
                            "🔊 AI UPLINK PCM → ${pcmCopy.size} bytes"
                        )


                        recordAiResponsePcm(
                            pcmCopy
                        )

                        audioInjector.writePcmData(
                            pcmCopy
                        )


                    } catch (e: Exception) {

                        Log.e(
                            TAG,
                            "❌ AI PCM injection failed",
                            e
                        )
                    }
                }
            }
        }


    // ================================================================
    // SERVICE CREATED
    // ================================================================

    override fun onCreate() {

        super.onCreate()


        Log.i(
            TAG,
            "================================"
        )

        Log.i(
            TAG,
            "🚀 AppInCallService CREATED"
        )

        Log.i(
            TAG,
            "Package = $packageName"
        )

        Log.i(
            TAG,
            "RX source = VOICE_DOWNLINK (${MediaRecorder.AudioSource.VOICE_DOWNLINK})"
        )

        Log.i(
            TAG,
            "Sample rate = $SAMPLE_RATE"
        )

        Log.i(
            TAG,
            "================================"
        )


        audioManager =
            getSystemService(
                Context.AUDIO_SERVICE
            ) as AudioManager


        initializeAiResponseRecorder()


        try {

            registerReceiver(
                aiModeReceiver,
                IntentFilter(
                    ACTION_TOGGLE_AI_MODE
                )
            )


            registerReceiver(
                audioInjectionReceiver,
                IntentFilter(
                    ACTION_INJECT_UPLINK_AUDIO
                )
            )


            Log.i(
                TAG,
                "✅ Broadcast receivers registered"
            )


        } catch (e: Exception) {

            Log.e(
                TAG,
                "❌ Failed registering receivers",
                e
            )
        }
    }


    // ================================================================
    // CALL ADDED
    // ================================================================

    override fun onCallAdded(
        call: Call
    ) {

        super.onCallAdded(call)

        currentCall = call

        callEnded.set(false)
        hangupHandled.set(false)

        Log.i(
            TAG,
            "📞 onCallAdded() | state=${call.state}"
        )

        logCallState(
            call.state
        )

        callCallback =
            object : Call.Callback() {

                override fun onStateChanged(
                    call: Call,
                    state: Int
                ) {

                    Log.i(
                        TAG,
                        "📱 CALL STATE CHANGED = $state"
                    )

                    logCallState(
                        state
                    )

                    when (state) {

                        Call.STATE_ACTIVE -> {

                            if (callEnded.get()) {

                                Log.w(
                                    TAG,
                                    "⚠️ ACTIVE received after call ended"
                                )

                                return
                            }

                            Log.i(
                                TAG,
                                "🟢 CALL ACTIVE"
                            )

                            startAiResponseRecordingSession()

                            startAudioCapture()
                        }

                        Call.STATE_DISCONNECTING -> {

                            Log.i(
                                TAG,
                                "🔴 CALL DISCONNECTING"
                            )

                            Log.i(
                                TAG,
                                "📴 Telecom is terminating the call"
                            )

                            handleCallHangup()
                        }

                        Call.STATE_DISCONNECTED -> {

                            Log.i(
                                TAG,
                                "=========================================="
                            )

                            Log.i(
                                TAG,
                                "🔴 CALL DISCONNECTED"
                            )

                            Log.i(
                                TAG,
                                "✅ LOCAL TELECOM CALL IS DISCONNECTED"
                            )

                            Log.i(
                                TAG,
                                "📱 Final state = ${call.state}"
                            )

                            Log.i(
                                TAG,
                                "📴 Disconnect cause = ${call.details.disconnectCause}"
                            )

                            Log.i(
                                TAG,
                                "=========================================="
                            )

                            handleCallHangup()

                            // Restore microphone only after Telecom confirms DISCONNECTED.
                            disableAiMode()
                        }
                    }
                }
            }

        call.registerCallback(
            callCallback!!
        )

        if (
            call.state ==
            Call.STATE_ACTIVE
        ) {

            Log.i(
                TAG,
                "🟢 Call already ACTIVE"
            )

            startAiResponseRecordingSession()

            startAudioCapture()
        }

        if (
            call.state ==
            Call.STATE_DISCONNECTED
        ) {

            Log.w(
                TAG,
                "🔴 Call already DISCONNECTED during onCallAdded()"
            )

            handleCallHangup()

            disableAiMode()
        }
    }


    // ================================================================
    // CALL REMOVED
    // ================================================================

 override fun onCallRemoved(
    call: Call
) {

    Log.i(
        TAG,
        "📴 onCallRemoved()"
    )

    Log.i(
        TAG,
        "✅ CALL REMOVED FROM LOCAL TELECOM"
    )

    Log.i(
        TAG,
        "📱 Removed call state = ${call.state}"
    )


    if (
        call == currentCall
    ) {

        handleCallHangup()

        finalizeSessionRecording()


        // Final safety restore.
        disableAiMode()


        callCallback?.let { callback ->

            try {

                call.unregisterCallback(
                    callback
                )

            } catch (e: Exception) {

                Log.e(
                    TAG,
                    "❌ Failed unregistering callback",
                    e
                )
            }
        }


        callCallback = null
        currentCall = null
    }


    super.onCallRemoved(call)
}
    // ================================================================
    // CALL HANGUP
    // ================================================================

    private fun handleCallHangup() {

                        if (
                            !hangupHandled.compareAndSet(
                                false,
                                true
                            )
                        ) {

                            Log.d(
                                TAG,
                                "🛑 Call hangup already handled"
                            )

                            return
                        }


                        callEnded.set(true)


                        Log.i(
                            TAG,
                            "🛑 CALL TERMINATING"
                        )


                        stopAudioCapture()

                        stopAudioInjector()

                        stopAiResponseRecordingSession()


                        // IMPORTANT:
                        // Do NOT restore the local mic here.
                        // Wait until Telecom confirms DISCONNECTED.


                        try {

                            sendBroadcast(
                                Intent(
                                    ACTION_CALL_DISCONNECTED
                                )
                            )

                        } catch (e: Exception) {

                            Log.e(
                                TAG,
                                "❌ Failed sending disconnect broadcast",
                                e
                            )
                        }
                    }
    // ================================================================
    // CALL STATE LOGGING
    // ================================================================

    private fun logCallState(
        state: Int
    ) {

        when (state) {

            Call.STATE_NEW ->
                Log.i(
                    TAG,
                    "📱 CALL STATE = NEW"
                )


            Call.STATE_CONNECTING ->
                Log.i(
                    TAG,
                    "📱 CALL STATE = CONNECTING"
                )


            Call.STATE_DIALING ->
                Log.i(
                    TAG,
                    "📱 CALL STATE = DIALING"
                )


            Call.STATE_RINGING ->
                Log.i(
                    TAG,
                    "📱 CALL STATE = RINGING"
                )


            Call.STATE_ACTIVE ->
                Log.i(
                    TAG,
                    "📱 CALL STATE = ACTIVE"
                )


            Call.STATE_HOLDING ->
                Log.i(
                    TAG,
                    "📱 CALL STATE = HOLDING"
                )


            Call.STATE_DISCONNECTING ->
                Log.i(
                    TAG,
                    "📱 CALL STATE = DISCONNECTING"
                )


            Call.STATE_DISCONNECTED ->
                Log.i(
                    TAG,
                    "📱 CALL STATE = DISCONNECTED"
                )


            else ->
                Log.i(
                    TAG,
                    "📱 CALL STATE = UNKNOWN($state)"
                )
        }
    }


    // ================================================================
    // AI MODE
    // ================================================================

    /**
     * DEBUG VERSION.
     *
     * IMPORTANT:
     *
     * We DO NOT set STREAM_VOICE_CALL volume to 0.
     *
     * Some vendor implementations may change the call RX
     * routing when call volume is forced to zero.
     */
    fun enableAiMode() {

        if (
            callEnded.get()
        ) {

            Log.w(
                TAG,
                "🤖 AI Mode rejected - call ended"
            )

            return
        }


        try {

            audioManager?.let { am ->

                /*
                 * Mute physical/local microphone.
                 *
                 * AI should provide uplink audio instead.
                 */
                am.isMicrophoneMute = true


                /*
                 * Keep speakerphone disabled.
                 */
                am.isSpeakerphoneOn = false


                /*
                 * DO NOT:
                 *
                 * am.setStreamVolume(
                 *     AudioManager.STREAM_VOICE_CALL,
                 *     0,
                 *     0
                 * )
                 */


                Log.i(
                    TAG,
                    "🤖 AI MODE ENABLED | local mic muted | call volume untouched"
                )
            }


        } catch (e: Exception) {

            Log.e(
                TAG,
                "❌ Failed enabling AI Mode",
                e
            )
        }
    }


    // ================================================================
    // DISABLE AI MODE
    // ================================================================

    fun disableAiMode() {

        try {

            audioManager?.let { am ->

                am.isMicrophoneMute = false

                am.isSpeakerphoneOn = false


                Log.i(
                    TAG,
                    "👤 AI MODE DISABLED | local mic restored"
                )
            }


        } catch (e: Exception) {

            Log.e(
                TAG,
                "❌ Failed disabling AI Mode",
                e
            )
        }
    }


    // ================================================================
    // START CUSTOMER DOWNLINK CAPTURE
    // ================================================================

    private fun startAudioCapture() {

        if (
            callEnded.get()
        ) {

            Log.w(
                TAG,
                "🎙 Cannot start capture - call ended"
            )

            return
        }


        if (
            audioRunning.get()
        ) {

            Log.i(
                TAG,
                "🎙 Capture already running"
            )

            return
        }


        Log.i(
            TAG,
            "=========================================="
        )

        Log.i(
            TAG,
            "🎙 STARTING CUSTOMER DOWNLINK CAPTURE"
        )

        Log.i(
            TAG,
            "🎯 AudioSource = VOICE_DOWNLINK"
        )

        Log.i(
            TAG,
            "🎯 SampleRate = $SAMPLE_RATE"
        )

        Log.i(
            TAG,
            "=========================================="
        )


        val minBuffer =
            AudioRecord.getMinBufferSize(
                SAMPLE_RATE,
                CHANNEL_CONFIG,
                AUDIO_FORMAT
            )


        if (
            minBuffer <= 0
        ) {

            Log.e(
                TAG,
                "❌ Invalid minBuffer=$minBuffer"
            )

            return
        }


        val bufferSize =
            max(
                minBuffer * 2,
                4096
            )


        Log.i(
            TAG,
            "🎙 AudioRecord minBuffer=$minBuffer requestedBuffer=$bufferSize"
        )


        try {

            startWavRecording()


            var initializedRecord:
                    AudioRecord? = null


            for (
                source in DOWNLINK_SOURCES
            ) {

                try {

                    Log.i(
                        TAG,
                        "🔄 Attempting VOICE_DOWNLINK source=$source"
                    )


                    val recorder =
                        AudioRecord(
                            source,
                            SAMPLE_RATE,
                            CHANNEL_CONFIG,
                            AUDIO_FORMAT,
                            bufferSize
                        )


                    Log.i(
                        TAG,
                        "🎙 AudioRecord state=${recorder.state}"
                    )


                    if (
                        recorder.state ==
                        AudioRecord.STATE_INITIALIZED
                    ) {

                        initializedRecord =
                            recorder


                        Log.i(
                            TAG,
                            "✅ VOICE_DOWNLINK AudioRecord INITIALIZED"
                        )


                        break


                    } else {

                        Log.e(
                            TAG,
                            "❌ VOICE_DOWNLINK AudioRecord NOT INITIALIZED"
                        )


                        recorder.release()
                    }


                } catch (
                    securityException:
                    SecurityException
                ) {

                    Log.e(
                        TAG,
                        "❌ VOICE_DOWNLINK SecurityException. Check CAPTURE_AUDIO_OUTPUT.",
                        securityException
                    )


                } catch (
                    e: Exception
                ) {

                    Log.e(
                        TAG,
                        "❌ VOICE_DOWNLINK initialization error",
                        e
                    )
                }
            }


            audioRecord =
                initializedRecord


            if (
                audioRecord == null ||
                audioRecord?.state !=
                AudioRecord.STATE_INITIALIZED
            ) {

                Log.e(
                    TAG,
                    "❌ CUSTOMER DOWNLINK unavailable"
                )


                Log.e(
                    TAG,
                    "❌ NO MIC fallback will be used"
                )


                audioRecord?.release()

                audioRecord = null


                stopWavRecording()


                return
            }


            if (
                callEnded.get() ||
                currentCall?.state !=
                Call.STATE_ACTIVE
            ) {

                Log.w(
                    TAG,
                    "⚠️ Call no longer ACTIVE before AudioRecord start"
                )


                audioRecord?.release()

                audioRecord = null


                stopWavRecording()


                return
            }


            /*
             * Mark capture running.
             */
            audioRunning.set(true)


            /*
             * IMPORTANT:
             *
             * During customer RX debugging,
             * DO NOT automatically start AI injection.
             */
            if (
                ENABLE_AI_INJECTOR_DURING_RX_TEST
            ) {

                ensureAudioInjectorStarted()


            } else {

                Log.w(
                    TAG,
                    "🧪 DEBUG MODE: AI injector NOT auto-started"
                )
            }


            audioRecord?.startRecording()


            Log.i(
                TAG,
                "🎙 AudioRecord recordingState=${audioRecord?.recordingState}"
            )


            if (
                audioRecord?.recordingState !=
                AudioRecord.RECORDSTATE_RECORDING
            ) {

                Log.e(
                    TAG,
                    "❌ AudioRecord failed to enter RECORDING state"
                )


                stopAudioCapture()

                return
            }


            if (
                callEnded.get()
            ) {

                Log.w(
                    TAG,
                    "⚠️ Call ended during AudioRecord startup"
                )


                stopAudioCapture()

                return
            }


            audioExecutor =
                Executors
                    .newSingleThreadExecutor()


            audioExecutor?.execute {

                audioCaptureLoop()
            }


            Log.i(
                TAG,
                "🎙 CUSTOMER RX THREAD STARTED"
            )


        } catch (e: Exception) {

            Log.e(
                TAG,
                "❌ Customer downlink start failed",
                e
            )


            stopAudioCapture()
        }
    }


    // ================================================================
    // AUDIO STATISTICS
    // ================================================================

    private fun calculateAudioStats(
        pcm: ByteArray
    ): AudioStats {

        var peak = 0

        var sumSquares = 0.0

        var nonZeroSamples = 0

        var totalSamples = 0


        var i = 0


        while (
            i + 1 <
            pcm.size
        ) {

            val low =
                pcm[i].toInt() and 0xFF


            val high =
                pcm[i + 1].toInt()


            val sample =
                (
                    (high shl 8) or
                    low
                )
                    .toShort()
                    .toInt()


            val amplitude =
                abs(
                    sample
                )


            if (
                amplitude >
                peak
            ) {

                peak =
                    amplitude
            }


            if (
                sample != 0
            ) {

                nonZeroSamples++
            }


            sumSquares +=
                sample.toDouble() *
                sample.toDouble()


            totalSamples++


            i += 2
        }


        val rms =
            if (
                totalSamples > 0
            ) {

                sqrt(
                    sumSquares /
                    totalSamples
                )

            } else {

                0.0
            }


        return AudioStats(
            peak = peak,
            rms = rms,
            nonZeroSamples =
                nonZeroSamples,
            totalSamples =
                totalSamples
        )
    }


    // ================================================================
    // CUSTOMER DOWNLINK CAPTURE LOOP
    // ================================================================

                    private fun audioCaptureLoop() {

                    val buffer = ByteArray(2048)

                    var readCount = 0
                    var totalBytes: Long = 0

                    Log.i(TAG, "==========================================")
                    Log.i(TAG, "🎙 CUSTOMER DOWNLINK LOOP ACTIVE")
                    Log.i(TAG, "🎯 Waiting for REMOTE CUSTOMER speech")
                    Log.i(TAG, "==========================================")

                    while (audioRunning.get()) {

                        if (callEnded.get()) {
                            Log.i(
                                TAG,
                                "🛑 Call ended before RX frame"
                            )
                            break
                        }

                        val count =
                            try {

                                audioRecord?.read(
                                    buffer,
                                    0,
                                    buffer.size
                                ) ?: -1

                            } catch (e: Exception) {

                                Log.e(
                                    TAG,
                                    "❌ AudioRecord.read failed",
                                    e
                                )

                                -1
                            }

                        if (callEnded.get()) {

                            Log.i(
                                TAG,
                                "🛑 Discarding frame during call teardown"
                            )

                            break
                        }

                        if (
                            count > 0 &&
                            audioRunning.get()
                        ) {

                            readCount++

                            totalBytes += count

                            val customerPcm =
                                buffer.copyOf(count)

                            val stats =
                                calculateAudioStats(
                                    customerPcm
                                )

                            // ====================================================
                            // SAVE EXACT CUSTOMER PCM
                            // ====================================================

                            writeWavData(
                                customerPcm
                            )

                            // ====================================================
                            // DEBUG AUDIO LEVEL
                            // ====================================================

                            if (readCount % 5 == 0) {

                                Log.d(
                                    TAG,
                                    "🔊 CUSTOMER RX | " +
                                            "frame=$readCount | " +
                                            "bytes=$count | " +
                                            "peak=${stats.peak} | " +
                                            "rms=${stats.rms} | " +
                                            "nonZero=${stats.nonZeroSamples}/${stats.totalSamples}"
                                )
                            }

                        // ====================================================
                        // CUSTOMER PCM → FLUTTER
                        // ====================================================

                        if (!callEnded.get() && audioRunning.get()) {

                            val channel =
                                MainActivity.getMethodChannel()

                            if (channel == null) {

                                Log.e(
                                    TAG,
                                    "❌ CUSTOMER PCM NOT SENT | " +
                                            "MethodChannel=NULL"
                                )

                            } else {

                                // IMPORTANT:
                                // Make a copy of the PCM data before posting
                                // to the main thread.
                                //
                                // This prevents the AudioRecord buffer from
                                // being overwritten before Flutter receives it.
                                val pcmCopy =
                                    customerPcm.copyOf()

                                val currentFrame =
                                    readCount

                                if (currentFrame % 5 == 0) {

                                    Log.d(
                                        TAG,
                                        "📤 CUSTOMER PCM → FLUTTER | " +
                                                "frame=$currentFrame | " +
                                                "bytes=${pcmCopy.size}"
                                    )
                                }

                                mainHandler.post {

                                    // Check again because call state may have
                                    // changed while waiting for main thread.
                                    if (
                                        callEnded.get() ||
                                        !audioRunning.get()
                                    ) {

                                        if (currentFrame % 5 == 0) {

                                            Log.w(
                                                TAG,
                                                "⚠️ CUSTOMER PCM SEND CANCELLED | " +
                                                        "frame=$currentFrame | " +
                                                        "callEnded=${callEnded.get()} | " +
                                                        "audioRunning=${audioRunning.get()}"
                                            )
                                        }

                                        return@post
                                    }

                                    try {

                                        channel.invokeMethod(
                                            "onCustomerDownlinkAudioReceived",
                                            pcmCopy,
                                            object :
                                                io.flutter.plugin.common.MethodChannel.Result {

                                                override fun success(
                                                    result: Any?
                                                ) {

                                                    if (
                                                        currentFrame % 5 == 0
                                                    ) {

                                                        Log.d(
                                                            TAG,
                                                            "✅ FLUTTER ACK CUSTOMER PCM | " +
                                                                    "frame=$currentFrame | " +
                                                                    "bytes=${pcmCopy.size} | " +
                                                                    "result=$result"
                                                        )
                                                    }
                                                }

                                                override fun error(
                                                    errorCode: String,
                                                    errorMessage: String?,
                                                    errorDetails: Any?
                                                ) {

                                                    Log.e(
                                                        TAG,
                                                        "❌ FLUTTER CUSTOMER PCM ERROR | " +
                                                                "frame=$currentFrame | " +
                                                                "code=$errorCode | " +
                                                                "message=$errorMessage | " +
                                                                "details=$errorDetails"
                                                    )
                                                }

                                                override fun notImplemented() {

                                                    Log.e(
                                                        TAG,
                                                        "❌ FLUTTER METHOD NOT IMPLEMENTED | " +
                                                                "frame=$currentFrame | " +
                                                                "method=" +
                                                                "onCustomerDownlinkAudioReceived"
                                                    )
                                                }
                                            }
                                        )

                                    } catch (
                                        e: Exception
                                    ) {

                                        Log.e(
                                            TAG,
                                            "❌ CUSTOMER PCM invokeMethod exception | " +
                                                    "frame=$currentFrame | " +
                                                    "bytes=${pcmCopy.size}",
                                            e
                                        )
                                    }
                                }
                            }
                        

                        }
                        // ====================================================
                        // AUDIORECORD ERROR HANDLING
                        // ====================================================

                        } else if (
                            count ==
                            AudioRecord.ERROR_INVALID_OPERATION
                        ) {

                            Log.e(
                                TAG,
                                "❌ AudioRecord ERROR_INVALID_OPERATION"
                            )

                            break

                        } else if (
                            count ==
                            AudioRecord.ERROR_BAD_VALUE
                        ) {

                            Log.e(
                                TAG,
                                "❌ AudioRecord ERROR_BAD_VALUE"
                            )

                            break

                        } else if (
                            count ==
                            AudioRecord.ERROR_DEAD_OBJECT
                        ) {

                            Log.e(
                                TAG,
                                "❌ AudioRecord ERROR_DEAD_OBJECT"
                            )

                            break

                        } else if (
                            count < 0
                        ) {

                            Log.e(
                                TAG,
                                "❌ AudioRecord read error=$count"
                            )

                            break
                        }

                        // ====================================================
                        // SMALL LOOP DELAY
                        // ====================================================

                        try {

                            Thread.sleep(5)

                        } catch (
                            e: InterruptedException
                        ) {

                            Thread.currentThread()
                                .interrupt()

                            Log.w(
                                TAG,
                                "⚠️ CUSTOMER RX thread interrupted"
                            )

                            break
                        }

                        }

// ====================================================
// CUSTOMER RX LOOP FINISHED
// ====================================================

Log.i(
    TAG,
    "🎙 CUSTOMER RX LOOP TERMINATED | " +
            "frames=$readCount | " +
            "bytes=$totalBytes"
)
    }
    // ================================================================
    // START AI INJECTOR
    // ================================================================

    private fun ensureAudioInjectorStarted() {

        if (
            injectorStarted.compareAndSet(
                false,
                true
            )
        ) {

            try {

                audioInjector.start()


                Log.i(
                    TAG,
                    "🔊 AI audio injector STARTED"
                )


            } catch (
                e: Exception
            ) {

                injectorStarted.set(
                    false
                )


                Log.e(
                    TAG,
                    "❌ AI injector start failed",
                    e
                )


                throw e
            }
        }
    }


    // ================================================================
    // STOP AI INJECTOR
    // ================================================================

    private fun stopAudioInjector() {

        if (
            injectorStarted.compareAndSet(
                true,
                false
            )
        ) {

            try {

                audioInjector.stop()


                Log.i(
                    TAG,
                    "🔇 AI audio injector STOPPED"
                )


            } catch (
                e: Exception
            ) {

                Log.e(
                    TAG,
                    "❌ Error stopping AI injector",
                    e
                )
            }
        }
    }


    // ================================================================
    // START WAV RECORDING
    // ================================================================

    private fun startWavRecording() {

        try {

            /*
             * IMPORTANT:
             *
             * Use ONE location for both chunks and final recordings.
             *
             * This avoids renameTo() failing between
             * internal and external storage.
             */
            val directory =
                File(
                    getExternalFilesDir(
                        null
                    ),
                    "call_recordings"
                )


            if (
                !directory.exists()
            ) {

                val created =
                    directory.mkdirs()


                if (
                    !created &&
                    !directory.exists()
                ) {

                    Log.e(
                        TAG,
                        "❌ Cannot create recording directory"
                    )


                    return
                }
            }


            chunkIndex++


            val fileName =
                "customer_rx_chunk_" +
                        "${chunkIndex}_" +
                        "${System.currentTimeMillis()}.wav"


            wavFile =
                File(
                    directory,
                    fileName
                )


            wavOutput =
                FileOutputStream(
                    wavFile
                )


            wavDataSize = 0


            /*
             * Reserve 44-byte WAV header.
             */
            wavOutput?.write(
                ByteArray(44)
            )


            wavFile?.let { file ->

                sessionChunkFiles.add(
                    file
                )


                Log.i(
                    TAG,
                    "💾 CUSTOMER RX WAV initialized"
                )


                Log.i(
                    TAG,
                    "📁 ${file.absolutePath}"
                )
            }


        } catch (
            e: Exception
        ) {

            Log.e(
                TAG,
                "❌ WAV initialization failed",
                e
            )
        }
    }


    // ================================================================
    // WRITE PCM TO WAV
    // ================================================================

    private fun writeWavData(
        pcm: ByteArray
    ) {

        try {

            wavOutput?.write(
                pcm
            )


            wavDataSize +=
                pcm.size


        } catch (
            e: Exception
        ) {

            Log.e(
                TAG,
                "❌ WAV write failed",
                e
            )
        }
    }


    // ================================================================
    // STOP / FINALIZE CURRENT WAV
    // ================================================================

    private fun stopWavRecording() {

        val file =
            wavFile ?: return


        val output =
            wavOutput ?: return


        try {

            output.flush()

            output.close()

            wavOutput = null


            RandomAccessFile(
                file,
                "rw"
            ).use { raf ->

                raf.seek(
                    0
                )


                raf.writeBytes(
                    "RIFF"
                )


                raf.writeInt(
                    Integer.reverseBytes(
                        (
                            36 +
                            wavDataSize
                        ).toInt()
                    )
                )


                raf.writeBytes(
                    "WAVE"
                )


                raf.writeBytes(
                    "fmt "
                )


                raf.writeInt(
                    Integer.reverseBytes(
                        16
                    )
                )


                /*
                 * PCM format = 1
                 */
                raf.writeShort(
                    java.lang.Short
                        .reverseBytes(
                            1.toShort()
                        )
                        .toInt()
                )


                /*
                 * Mono = 1
                 */
                raf.writeShort(
                    java.lang.Short
                        .reverseBytes(
                            1.toShort()
                        )
                        .toInt()
                )


                /*
                 * Sample rate.
                 */
                raf.writeInt(
                    Integer.reverseBytes(
                        SAMPLE_RATE
                    )
                )


                /*
                 * Byte Rate =
                 *
                 * sample rate *
                 * channels *
                 * bytes/sample
                 */
                raf.writeInt(
                    Integer.reverseBytes(
                        SAMPLE_RATE * 2
                    )
                )


                /*
                 * Block align.
                 */
                raf.writeShort(
                    java.lang.Short
                        .reverseBytes(
                            2.toShort()
                        )
                        .toInt()
                )


                /*
                 * 16 bits/sample.
                 */
                raf.writeShort(
                    java.lang.Short
                        .reverseBytes(
                            16.toShort()
                        )
                        .toInt()
                )


                raf.writeBytes(
                    "data"
                )


                raf.writeInt(
                    Integer.reverseBytes(
                        wavDataSize.toInt()
                    )
                )
            }


            Log.i(
                TAG,
                "💾 CUSTOMER RX WAV finalized: " +
                        "${file.absolutePath} | " +
                        "$wavDataSize bytes"
            )


        } catch (
            e: Exception
        ) {

            Log.e(
                TAG,
                "❌ WAV finalization failed",
                e
            )


        } finally {

            wavFile = null

            wavOutput = null

            wavDataSize = 0
        }
    }


    // ================================================================
    // FINALIZE COMPLETE CALL SESSION
    // ================================================================

    private fun finalizeSessionRecording() {

        if (
            sessionChunkFiles.isEmpty()
        ) {

            return
        }


        /*
         * Same external directory used for chunks.
         */
        val directory =
            File(
                getExternalFilesDir(
                    null
                ),
                "call_recordings"
            )


        if (
            !directory.exists()
        ) {

            directory.mkdirs()
        }


        val finalFile =
            File(
                directory,
                "customer_rx_session_" +
                        "${System.currentTimeMillis()}.wav"
            )


        if (
            sessionChunkFiles.size ==
            1
        ) {

            val source =
                sessionChunkFiles[0]


            if (
                source.exists()
            ) {

                try {

                    /*
                     * renameTo() may still fail on some devices.
                     *
                     * Therefore try rename first,
                     * then fallback to copy.
                     */
                    val renamed =
                        source.renameTo(
                            finalFile
                        )


                    if (
                        renamed
                    ) {

                        Log.i(
                            TAG,
                            "💾 Session recording renamed: ${finalFile.absolutePath}"
                        )


                    } else {

                        Log.w(
                            TAG,
                            "⚠️ renameTo failed - copying instead"
                        )


                        copyFile(
                            source,
                            finalFile
                        )


                        if (
                            finalFile.exists()
                        ) {

                            source.delete()


                            Log.i(
                                TAG,
                                "💾 Session recording copied: ${finalFile.absolutePath}"
                            )
                        }
                    }


                } catch (
                    e: Exception
                ) {

                    Log.e(
                        TAG,
                        "❌ Single WAV finalization failed",
                        e
                    )
                }
            }


        } else {

            mergeWavFiles(
                sessionChunkFiles,
                finalFile
            )
        }


        sessionChunkFiles.clear()
    }


    // ================================================================
    // COPY FILE
    // ================================================================

    private fun copyFile(
        source: File,
        destination: File
    ) {

        FileInputStream(
            source
        ).use { input ->

            FileOutputStream(
                destination
            ).use { output ->

                input.copyTo(
                    output
                )
            }
        }
    }


    // ================================================================
    // MERGE MULTIPLE WAV FILES
    // ================================================================

    private fun mergeWavFiles(
        inputFiles: List<File>,
        outputFile: File
    ) {

        var totalAudioLen =
            0L


        inputFiles.forEach { file ->

            if (
                file.exists() &&
                file.length() >
                44
            ) {

                totalAudioLen +=
                    file.length() -
                    44
            }
        }


        if (
            totalAudioLen <=
            0
        ) {

            Log.e(
                TAG,
                "❌ No audio data available for WAV merge"
            )


            return
        }


        val totalDataLen =
            totalAudioLen +
            36


        val byteRate =
            (
                SAMPLE_RATE *
                1 *
                2
            ).toLong()


        try {

            FileOutputStream(
                outputFile
            ).use { out ->

                val header =
                    ByteArray(
                        44
                    )


                // RIFF
                header[0] =
                    'R'.code.toByte()

                header[1] =
                    'I'.code.toByte()

                header[2] =
                    'F'.code.toByte()

                header[3] =
                    'F'.code.toByte()


                header[4] =
                    (
                        totalDataLen and
                        0xFF
                    ).toByte()

                header[5] =
                    (
                        totalDataLen shr 8 and
                        0xFF
                    ).toByte()

                header[6] =
                    (
                        totalDataLen shr 16 and
                        0xFF
                    ).toByte()

                header[7] =
                    (
                        totalDataLen shr 24 and
                        0xFF
                    ).toByte()


                // WAVE
                header[8] =
                    'W'.code.toByte()

                header[9] =
                    'A'.code.toByte()

                header[10] =
                    'V'.code.toByte()

                header[11] =
                    'E'.code.toByte()


                // fmt
                header[12] =
                    'f'.code.toByte()

                header[13] =
                    'm'.code.toByte()

                header[14] =
                    't'.code.toByte()

                header[15] =
                    ' '.code.toByte()


                header[16] = 16

                header[17] = 0

                header[18] = 0

                header[19] = 0


                // PCM
                header[20] = 1

                header[21] = 0


                // mono
                header[22] = 1

                header[23] = 0


                // sample rate
                header[24] =
                    (
                        SAMPLE_RATE and
                        0xFF
                    ).toByte()

                header[25] =
                    (
                        SAMPLE_RATE shr 8 and
                        0xFF
                    ).toByte()

                header[26] =
                    (
                        SAMPLE_RATE shr 16 and
                        0xFF
                    ).toByte()

                header[27] =
                    (
                        SAMPLE_RATE shr 24 and
                        0xFF
                    ).toByte()


                // byte rate
                header[28] =
                    (
                        byteRate and
                        0xFF
                    ).toByte()

                header[29] =
                    (
                        byteRate shr 8 and
                        0xFF
                    ).toByte()

                header[30] =
                    (
                        byteRate shr 16 and
                        0xFF
                    ).toByte()

                header[31] =
                    (
                        byteRate shr 24 and
                        0xFF
                    ).toByte()


                // block align
                header[32] = 2

                header[33] = 0


                // bits/sample
                header[34] = 16

                header[35] = 0


                // data
                header[36] =
                    'd'.code.toByte()

                header[37] =
                    'a'.code.toByte()

                header[38] =
                    't'.code.toByte()

                header[39] =
                    'a'.code.toByte()


                header[40] =
                    (
                        totalAudioLen and
                        0xFF
                    ).toByte()

                header[41] =
                    (
                        totalAudioLen shr 8 and
                        0xFF
                    ).toByte()

                header[42] =
                    (
                        totalAudioLen shr 16 and
                        0xFF
                    ).toByte()

                header[43] =
                    (
                        totalAudioLen shr 24 and
                        0xFF
                    ).toByte()


                out.write(
                    header
                )


                val buffer =
                    ByteArray(
                        4096
                    )


                inputFiles.forEach { file ->

                    if (
                        !file.exists() ||
                        file.length() <=
                        44
                    ) {

                        return@forEach
                    }


                    FileInputStream(
                        file
                    ).use { input ->

                        input.skip(
                            44
                        )


                        var bytesRead:
                                Int


                        while (
                            input.read(
                                buffer
                            ).also {
                                bytesRead = it
                            } != -1
                        ) {

                            out.write(
                                buffer,
                                0,
                                bytesRead
                            )
                        }
                    }
                }
            }


            /*
             * Delete source chunks only
             * after successful merge.
             */
            inputFiles.forEach { file ->

                if (
                    file.exists() &&
                    file != outputFile
                ) {

                    file.delete()
                }
            }


            Log.i(
                TAG,
                "💾 CUSTOMER RX session merged: ${outputFile.absolutePath}"
            )


        } catch (
            e: Exception
        ) {

            Log.e(
                TAG,
                "❌ WAV merge failed",
                e
            )
        }
    }


    // ================================================================
    // STOP AUDIO CAPTURE
    // ================================================================

    private fun stopAudioCapture() {

        /*
         * Block future frames FIRST.
         */
        audioRunning.set(
            false
        )


        Log.i(
            TAG,
            "🛑 Stopping CUSTOMER RX capture"
        )


        try {

            audioRecord?.let { record ->

                if (
                    record.recordingState ==
                    AudioRecord.RECORDSTATE_RECORDING
                ) {

                    record.stop()
                }


                record.release()
            }


        } catch (
            e: Exception
        ) {

            Log.e(
                TAG,
                "❌ AudioRecord release error",
                e
            )
        }


        audioRecord = null


        try {

            audioExecutor
                ?.shutdownNow()


        } catch (
            e: Exception
        ) {

            Log.e(
                TAG,
                "❌ Audio executor shutdown error",
                e
            )
        }


        audioExecutor = null


        /*
         * Remove pending Flutter frames.
         */
        mainHandler
            .removeCallbacksAndMessages(
                null
            )


        stopWavRecording()


        Log.i(
            TAG,
            "🛑 CUSTOMER RX capture stopped"
        )
    }


    // ================================================================
    // AI RESPONSE RECORDER INITIALIZATION
    // ================================================================

    private fun initializeAiResponseRecorder() {

        aiResponseRecorder =
            CallAiResponseRecorder(
                object : CallAiResponseRecorder.Listener {

                    override fun onAiResponseRecordingStarted(
                        responseNumber: Int,
                        filePath: String
                    ) {

                        Log.i(
                            TAG,
                            "🤖 AI response recording started #$responseNumber"
                        )
                    }


                    override fun onAiResponseCreated(
                        filePath: String,
                        responseNumber: Int,
                        durationMs: Long,
                        audioBytes: Long
                    ) {

                        Log.i(
                            TAG,
                            "💾 AI response saved: $filePath"
                        )


                        mainHandler.post {

                            try {

                                MainActivity
                                    .getMethodChannel()
                                    ?.invokeMethod(
                                        "onAiResponseAudioCreated",
                                        mapOf(
                                            "filePath" to filePath,
                                            "responseNumber" to responseNumber,
                                            "durationMs" to durationMs,
                                            "audioBytes" to audioBytes
                                        )
                                    )

                            } catch (e: Exception) {

                                Log.e(
                                    TAG,
                                    "❌ Failed sending AI response callback to Flutter",
                                    e
                                )
                            }
                        }
                    }


                    override fun onAiResponseRecordingStopped() {

                        Log.i(
                            TAG,
                            "🤖 AI response recording stopped"
                        )
                    }


                    override fun onError(
                        error: String
                    ) {

                        Log.e(
                            TAG,
                            "❌ AI response recorder: $error"
                        )
                    }
                }
            )
    }


    // ================================================================
    // START AI RESPONSE RECORDING SESSION
    // ================================================================

    private fun startAiResponseRecordingSession() {

        if (
            !::aiResponseRecorder.isInitialized
        ) {

            Log.e(
                TAG,
                "❌ AI response recorder is not initialized"
            )

            return
        }


        if (
            aiResponseRecorder.isSessionActive()
        ) {

            return
        }


        try {

            val directory =
                File(
                    getExternalFilesDir(null),
                    "ai_response_audio"
                )


            val started =
                aiResponseRecorder.startSession(
                    directory
                )


            Log.i(
                TAG,
                "🤖 AI response recording session started=$started"
            )


        } catch (e: Exception) {

            Log.e(
                TAG,
                "❌ Failed starting AI response recording session",
                e
            )
        }
    }


    // ================================================================
    // RECORD AI RESPONSE PCM
    // ================================================================

    private fun recordAiResponsePcm(
        pcm: ByteArray
    ) {

        if (
            !::aiResponseRecorder.isInitialized ||
            !aiResponseRecorder.isSessionActive()
        ) {

            return
        }


        try {

            if (
                !aiResponseRecorder.isResponseRecording()
            ) {

                val started =
                    aiResponseRecorder.startResponse()


                if (
                    !started
                ) {

                    Log.e(
                        TAG,
                        "❌ Could not start AI response WAV"
                    )

                    return
                }
            }


            aiResponseRecorder.appendPcm(
                pcm
            )


        } catch (e: Exception) {

            Log.e(
                TAG,
                "❌ Failed recording AI response PCM",
                e
            )
        }
    }


    // ================================================================
    // FINISH CURRENT AI RESPONSE
    // ================================================================

    private fun finishCurrentAiResponse() {

        if (
            !::aiResponseRecorder.isInitialized
        ) {

            return
        }


        try {

            if (
                aiResponseRecorder.isResponseRecording()
            ) {

                aiResponseRecorder.finishResponse()
            }

        } catch (e: Exception) {

            Log.e(
                TAG,
                "❌ Failed finalizing AI response WAV",
                e
            )
        }
    }


    // ================================================================
    // STOP AI RESPONSE RECORDING SESSION
    // ================================================================

    private fun stopAiResponseRecordingSession() {

        if (
            !::aiResponseRecorder.isInitialized
        ) {

            return
        }


        try {

            finishCurrentAiResponse()

            if (
                aiResponseRecorder.isSessionActive()
            ) {

                aiResponseRecorder.stopSession()
            }

        } catch (e: Exception) {

            Log.e(
                TAG,
                "❌ Failed stopping AI response recording session",
                e
            )
        }
    }


    // ================================================================
    // SERVICE DESTROY
    // ================================================================

    override fun onDestroy() {

        Log.i(
            TAG,
            "🛑 AppInCallService DESTROYED"
        )


        callEnded.set(
            true
        )


        try {

            unregisterReceiver(
                audioInjectionReceiver
            )

        } catch (
            _: Exception
        ) {
        }


        try {

            unregisterReceiver(
                aiModeReceiver
            )

        } catch (
            _: Exception
        ) {
        }


        stopAudioCapture()


        stopAudioInjector()


        stopAiResponseRecordingSession()


        finalizeSessionRecording()


        disableAiMode()


        currentCall = null

        callCallback = null


        super.onDestroy()
    }
}
