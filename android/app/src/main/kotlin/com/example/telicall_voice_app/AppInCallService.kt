package com.example.telicall_voice_app

import android.content.Intent
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.telecom.Call
import android.telecom.InCallService
import android.util.Log
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class AppInCallService : InCallService() {

    companion object {

        private const val TAG =
            "AppInCallService"

        private const val ACTION_CALL_ANSWERED =
            "com.example.telicall_voice_app.CALL_ANSWERED"

        private const val ACTION_CALL_ENDED =
            "com.example.telicall_voice_app.CALL_ENDED"

        private const val ACTION_PCM_FRAME =
            "com.example.telicall_voice_app.PCM_DOWNLINK_FRAME"

        private const val ACTION_INJECT_AUDIO =
            "com.example.telicall_voice_app.INJECT_UPLINK_AUDIO"

        private const val SAMPLE_RATE = 16000

        private const val CHANNEL_CONFIG =
            AudioFormat.CHANNEL_IN_MONO

        private const val AUDIO_FORMAT =
            AudioFormat.ENCODING_PCM_16BIT
    }

    private var currentCall: Call? = null

    private var audioExecutor: ExecutorService? = null

    private val audioRunning =
        AtomicBoolean(false)

    private var audioRecord: AudioRecord? = null

    // ============================================================
    // SERVICE CREATED
    // ============================================================

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
            "================================"
        )
    }

    // ============================================================
    // SERVICE DESTROYED
    // ============================================================

    override fun onDestroy() {

        Log.i(
            TAG,
            "🛑 AppInCallService DESTROYED"
        )

        stopAudioCapture()

        currentCall = null

        super.onDestroy()
    }

    // ============================================================
    // CALL ADDED
    // ============================================================

    override fun onCallAdded(call: Call) {

        super.onCallAdded(call)

        Log.i(
            TAG,
            "📞 ================================="
        )

        Log.i(
            TAG,
            "📞 onCallAdded()"
        )

        Log.i(
            TAG,
            "📞 Call = $call"
        )

        Log.i(
            TAG,
            "📞 State = ${call.state}"
        )

        Log.i(
            TAG,
            "📞 Details = ${call.details}"
        )

        Log.i(
            TAG,
            "📞 ================================="
        )

        currentCall = call

        call.registerCallback(
            callCallback
        )

        handleCallState(
            call,
            call.state
        )
    }

    // ============================================================
    // CALL REMOVED
    // ============================================================

    override fun onCallRemoved(call: Call) {

        Log.i(
            TAG,
            "🔴 onCallRemoved()"
        )

        stopAudioCapture()

        sendBroadcast(
            Intent(ACTION_CALL_ENDED).apply {
                setPackage(packageName)
            }
        )

        try {

            call.unregisterCallback(
                callCallback
            )

        } catch (_: Exception) {
        }

        if (currentCall == call) {

            currentCall = null
        }

        super.onCallRemoved(call)
    }

    // ============================================================
    // CALL CALLBACK
    // ============================================================

    private val callCallback =
        object : Call.Callback() {

            override fun onStateChanged(
                call: Call,
                state: Int
            ) {

                Log.i(
                    TAG,
                    "📱 CALL STATE = ${stateToString(state)}"
                )

                handleCallState(
                    call,
                    state
                )
            }

            override fun onDetailsChanged(
                call: Call,
                details: Call.Details
            ) {

                Log.i(
                    TAG,
                    "📱 Call details changed"
                )
            }
        }

    // ============================================================
    // HANDLE CALL STATE
    // ============================================================


    private fun handleCallState(
        call: Call,
        state: Int
    ) {

        when (state) {

            Call.STATE_NEW -> {

                Log.i(
                    TAG,
                    "🆕 CALL NEW"
                )
            }

            Call.STATE_RINGING -> {

                Log.i(
                    TAG,
                    "🔔 CALL RINGING"
                )
            }

            Call.STATE_DIALING -> {

                Log.i(
                    TAG,
                    "📤 CALL DIALING"
                )
            }

            Call.STATE_CONNECTING -> {

                Log.i(
                    TAG,
                    "🔌 CALL CONNECTING"
                )
            }

            Call.STATE_ACTIVE -> {

                Log.i(
                    TAG,
                    "🟢 ================================="
                )

                Log.i(
                    TAG,
                    "🟢 CALL ACTIVE"
                )

                Log.i(
                    TAG,
                    "🟢 ================================="

                )

                sendBroadcast(
                    Intent(
                        ACTION_CALL_ANSWERED
                    ).apply {
                        setPackage(packageName)
                    }
                )

                /*
                * IMPORTANT:
                *
                * Start the AI audio pipeline ONLY after
                * Telecom reports STATE_ACTIVE.
                */
                startAudioCapture()
            }

            Call.STATE_HOLDING -> {

                Log.i(
                    TAG,
                    "⏸ CALL HOLDING"
                )
            }

            Call.STATE_DISCONNECTED -> {

                Log.i(
                    TAG,
                    "🔴 CALL DISCONNECTED"
                )

                stopAudioCapture()
            }

            Call.STATE_SELECT_PHONE_ACCOUNT -> {

                Log.i(
                    TAG,
                    "📱 SELECT PHONE ACCOUNT"
                )
            }

            else -> {

                Log.i(
                    TAG,
                    "📞 CALL STATE: $state"
                )
            }
        }
    }


    // ============================================================
    // STATE STRING
    // ============================================================


    private fun stateToString(
        state: Int
    ): String {

        return when (state) {

            Call.STATE_NEW ->
                "NEW"

            Call.STATE_CONNECTING ->
                "CONNECTING"

            Call.STATE_DIALING ->
                "DIALING"

            Call.STATE_RINGING ->
                "RINGING"

            Call.STATE_ACTIVE ->
                "ACTIVE"

            Call.STATE_HOLDING ->
                "HOLDING"

            Call.STATE_DISCONNECTED ->
                "DISCONNECTED"

            Call.STATE_SELECT_PHONE_ACCOUNT ->
                "SELECT_PHONE_ACCOUNT"

            else ->
                "UNKNOWN($state)"
        }
    }


    // ============================================================
    // AUDIO CAPTURE
    // ============================================================

    private fun startAudioCapture() {

        if (
            audioRunning.get()
        ) {

            Log.i(
                TAG,
                "🎙 Audio capture already running"
            )

            return
        }

        Log.i(
            TAG,
            "🎙 Starting audio pipeline"
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
                "❌ Invalid AudioRecord buffer size"
            )

            return
        }

        val bufferSize =
            maxOf(
                minBuffer * 2,
                4096
            )

        try {

            audioRecord =
                AudioRecord(
                    MediaRecorder.AudioSource.VOICE_RECOGNITION,
                    SAMPLE_RATE,
                    CHANNEL_CONFIG,
                    AUDIO_FORMAT,
                    bufferSize
                )

            if (
                audioRecord?.state !=
                AudioRecord.STATE_INITIALIZED
            ) {

                Log.e(
                    TAG,
                    "❌ AudioRecord failed to initialize"
                )

                audioRecord?.release()
                audioRecord = null

                return
            }

            audioRunning.set(true)

            audioRecord?.startRecording()

            audioExecutor =
                Executors.newSingleThreadExecutor()

            audioExecutor?.execute {

                audioCaptureLoop(
                    bufferSize
                )
            }

            Log.i(
                TAG,
                "🎙 Audio capture started"
            )

        } catch (e: Exception) {

            Log.e(
                TAG,
                "❌ AudioRecord start failed",
                e
            )

            stopAudioCapture()
        }
    }

    // ============================================================
    // AUDIO LOOP
    // ============================================================

    private fun audioCaptureLoop(
        bufferSize: Int
    ) {

        val buffer =
            ByteArray(bufferSize)

        while (
            audioRunning.get()
        ) {

            try {

                val count =
                    audioRecord?.read(
                        buffer,
                        0,
                        buffer.size
                    ) ?: -1

                if (count > 0) {

                    val pcm =
                        buffer.copyOf(count)

                    sendBroadcast(
                        Intent(
                            ACTION_PCM_FRAME
                        ).apply {

                            setPackage(
                                packageName
                            )

                            putExtra(
                                "pcm_bytes",
                                pcm
                            )
                        }
                    )
                }

            } catch (e: Exception) {

                Log.e(
                    TAG,
                    "❌ Audio capture loop error",
                    e
                )

                break
            }
        }

        Log.i(
            TAG,
            "🎙 Audio capture loop stopped"
        )
    }

    // ============================================================
    // STOP AUDIO
    // ============================================================

    private fun stopAudioCapture() {

        if (
            !audioRunning.getAndSet(false)
        ) {

            return
        }

        Log.i(
            TAG,
            "🛑 Stopping audio capture"
        )

        try {

            audioRecord?.stop()

        } catch (_: Exception) {
        }

        try {

            audioRecord?.release()

        } catch (_: Exception) {
        }

        audioRecord = null

        try {

            audioExecutor?.shutdownNow()

        } catch (_: Exception) {
        }

        audioExecutor = null
    }
}
