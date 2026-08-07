package com.example.telicall_voice_app

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack

import android.util.Log

class CallAudioInjector {

    companion object {
        private const val TAG = "CallAudioInjector"
        private const val SAMPLE_RATE = 16000
        private const val CHANNEL_MASK = AudioFormat.CHANNEL_OUT_MONO
        private const val ENCODING = AudioFormat.ENCODING_PCM_16BIT
    }

    private var audioTrack: AudioTrack? = null
    private var isPlaying = false

    @Synchronized
    fun start(): Boolean {
        if (isPlaying) {
            Log.d(TAG, "AudioTrack already running")
            return true
        }

        return try {
            val minBufferSize = AudioTrack.getMinBufferSize(
                SAMPLE_RATE,
                CHANNEL_MASK,
                ENCODING
            )

            if (minBufferSize <= 0) {
                Log.e(TAG, "Invalid AudioTrack buffer size: $minBufferSize")
                return false
            }

            val bufferSize = maxOf(
                minBufferSize * 2,
                SAMPLE_RATE / 2
            )

            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()

            val audioFormat = AudioFormat.Builder()
                .setEncoding(ENCODING)
                .setSampleRate(SAMPLE_RATE)
                .setChannelMask(CHANNEL_MASK)
                .build()

            val track = AudioTrack(
                audioAttributes,
                audioFormat,
                bufferSize,
                AudioTrack.MODE_STREAM,
                AudioManager.AUDIO_SESSION_ID_GENERATE
            )

            if (track.state != AudioTrack.STATE_INITIALIZED) {
                Log.e(TAG, "AudioTrack initialization failed")
                track.release()
                return false
            }

            track.play()

            audioTrack = track
            isPlaying = true

            Log.i(
                TAG,
                "AudioTrack started. sampleRate=$SAMPLE_RATE buffer=$bufferSize"
            )

            true

        } catch (e: Exception) {
            Log.e(TAG, "Failed to start AudioTrack", e)
            audioTrack?.release()
            audioTrack = null
            isPlaying = false
            false
        }
    }

    @Synchronized
    fun writePcmData(data: ByteArray): Boolean {
        if (!isPlaying || audioTrack == null) {
            Log.w(TAG, "writePcmData() ignored: AudioTrack is not running")
            return false
        }

        if (data.isEmpty()) {
            return true
        }

        return try {
            val written = audioTrack!!.write(
                data,
                0,
                data.size,
                AudioTrack.WRITE_BLOCKING
            )

            if (written < 0) {
                Log.e(TAG, "AudioTrack.write() failed: $written")
                false
            } else {
                Log.d(TAG, "PCM written: $written bytes")
                true
            }

        } catch (e: Exception) {
            Log.e(TAG, "PCM write failed", e)
            false
        }
    }

    @Synchronized
    fun stop() {
        isPlaying = false

        try {
            audioTrack?.let { track ->
                try {
                    if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                        track.stop()
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "AudioTrack stop error", e)
                }

                track.flush()
                track.release()
            }
        } catch (e: Exception) {
            Log.e(TAG, "AudioTrack release error", e)
        } finally {
            audioTrack = null
        }

        Log.i(TAG, "AudioTrack stopped")
    }

    fun isRunning(): Boolean {
        return isPlaying && audioTrack?.state == AudioTrack.STATE_INITIALIZED
    }
}