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
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL =
            "com.example.telicall_voice_app/telecom"

        private const val REQUEST_CALL_PHONE = 1001
        private const val REQUEST_ANSWER_PHONE = 1002
    }

    private var methodChannel: MethodChannel? = null
    private var callStateReceiver: BroadcastReceiver? = null
    private var isAiModeActive = false

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
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

            override fun onReceive(
                context: Context?,
                intent: Intent?
            ) {

                when (intent?.action) {

                    "com.example.telicall_voice_app.CALL_ANSWERED" -> {

                        println(
                            "📞 [NATIVE] CALL_ANSWERED received"
                        )

                        methodChannel?.invokeMethod(
                            "onCallAnswered",
                            null
                        )
                    }

                    "com.example.telicall_voice_app.CALL_ENDED" -> {

                        println(
                            "🔴 [NATIVE] CALL_ENDED received"
                        )

                        methodChannel?.invokeMethod(
                            "onCallEnded",
                            null
                        )
                    }

                    "com.example.telicall_voice_app.PCM_DOWNLINK_FRAME" -> {

                        val pcm =
                            intent.getByteArrayExtra("pcm_bytes")

                        if (pcm != null) {

                            methodChannel?.invokeMethod(
                                "onCallerAudioReceived",
                                pcm
                            )
                        }
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

            addAction(
                "com.example.telicall_voice_app.PCM_DOWNLINK_FRAME"
            )
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {

            registerReceiver(
                callStateReceiver,
                filter,
                Context.RECEIVER_NOT_EXPORTED
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
                // MAKE CALL
                // ------------------------------------------------

                "makeNativeInternalCall" -> {

                    val number =
                        call.argument<String>("phoneNumber")

                    isAiModeActive =
                        call.argument<Boolean>("isAiMode")
                            ?: false

                    if (number.isNullOrBlank()) {

                        result.error(
                            "INVALID_NUMBER",
                            "Phone number is empty",
                            null
                        )

                        return@setMethodCallHandler
                    }

                    if (
                        ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.CALL_PHONE
                        ) != PackageManager.PERMISSION_GRANTED
                    ) {

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

                    if (isAiModeActive) {

                        applyAiAudioMode()

                    } else {

                        restoreNormalAudio()
                    }

                    val success =
                        makeDirectTelecomCall(number)

                    result.success(success)
                }

                // ------------------------------------------------
                // AI AUDIO MODE
                // ------------------------------------------------

                "setAudioMode" -> {

                    val aiMode =
                        call.argument<Boolean>("isAiMode")
                            ?: false

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

                    val pcmData =
                        call.argument<ByteArray>("pcmData")

                    val wavPath =
                        call.argument<String>("filePath")

                    if (
                        pcmData == null &&
                        wavPath.isNullOrBlank()
                    ) {

                        result.error(
                            "INVALID_AUDIO",
                            "PCM data or WAV path missing",
                            null
                        )

                        return@setMethodCallHandler
                    }

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

                    sendBroadcast(intent)

                    result.success(true)
                }

                // ------------------------------------------------
                // HANG UP
                // ------------------------------------------------

                "disconnectCall" -> {

                    isAiModeActive = false

                    restoreNormalAudio()

                    result.success(
                        hangUpActiveCall()
                    )
                }

                // ------------------------------------------------
                // CHECK DIALER ROLE
                // ------------------------------------------------

                "checkDialerStatus" -> {

                    val resultValue =
                        checkDialerRole()

                    result.success(resultValue)
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
    // CHECK DIALER ROLE
    // ============================================================

    private fun checkDialerRole(): Boolean {

        return if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
        ) {

            val roleManager =
                getSystemService(
                    Context.ROLE_SERVICE
                ) as RoleManager

            roleManager.isRoleHeld(
                RoleManager.ROLE_DIALER
            )

        } else {

            val telecom =
                getSystemService(
                    Context.TELECOM_SERVICE
                ) as TelecomManager

            packageName ==
                    telecom.defaultDialerPackage
        }
    }

    // ============================================================
    // REQUEST DIALER ROLE
    // ============================================================

    private fun requestDefaultDialerRole() {

        if (
            Build.VERSION.SDK_INT >=
            Build.VERSION_CODES.Q
        ) {

            val roleManager =
                getSystemService(
                    Context.ROLE_SERVICE
                ) as RoleManager

            println(
                "☎️ DIALER ROLE AVAILABLE = " +
                        roleManager.isRoleAvailable(
                            RoleManager.ROLE_DIALER
                        )
            )

            println(
                "☎️ DIALER ROLE HELD = " +
                        roleManager.isRoleHeld(
                            RoleManager.ROLE_DIALER
                        )
            )

            if (
                roleManager.isRoleAvailable(
                    RoleManager.ROLE_DIALER
                ) &&
                !roleManager.isRoleHeld(
                    RoleManager.ROLE_DIALER
                )
            ) {

                val intent =
                    roleManager.createRequestRoleIntent(
                        RoleManager.ROLE_DIALER
                    )

                startActivityForResult(
                    intent,
                    5001
                )
            }

        } else {

            try {

                val intent =
                    Intent(
                        Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS
                    )

                startActivity(intent)

            } catch (e: Exception) {

                println(
                    "❌ Failed to open default apps: " +
                            e.message
                )
            }
        }
    }

    // ============================================================
    // PLACE CALL
    // ============================================================

    private fun makeDirectTelecomCall(
        number: String
    ): Boolean {

        var cleanNumber =
            number.replace(
                "[^0-9+]".toRegex(),
                ""
            )

        if (
            cleanNumber.length == 10 &&
            !cleanNumber.startsWith("+")
        ) {

            cleanNumber =
                "+91$cleanNumber"
        }

        val uri =
            Uri.parse(
                "tel:$cleanNumber"
            )

        return try {

            val telecom =
                getSystemService(
                    Context.TELECOM_SERVICE
                ) as TelecomManager

            val extras =
                Bundle()

            // Select SIM
            val accounts =
                telecom.callCapablePhoneAccounts

            if (
                accounts != null &&
                accounts.isNotEmpty()
            ) {

                extras.putParcelable(
                    TelecomManager
                        .EXTRA_PHONE_ACCOUNT_HANDLE,
                    accounts[0]
                )

                println(
                    "📱 Using SIM account: " +
                            accounts[0]
                )

            } else {

                val selected =
                    telecom
                        .getUserSelectedOutgoingPhoneAccount()

                if (selected != null) {

                    extras.putParcelable(
                        TelecomManager
                            .EXTRA_PHONE_ACCOUNT_HANDLE,
                        selected
                    )
                }
            }

            extras.putBoolean(
                TelecomManager
                    .EXTRA_START_CALL_WITH_SPEAKERPHONE,
                false
            )

            telecom.placeCall(
                uri,
                extras
            )

            println(
                "📞 [TELECOM] Call placed: $cleanNumber"
            )

            true

        } catch (e: Exception) {

            println(
                "❌ Telecom placeCall failed: " +
                        e.message
            )

            false
        }
    }

    // ============================================================
    // HANG UP
    // ============================================================

    private fun hangUpActiveCall(): Boolean {

        return try {

            val telecom =
                getSystemService(
                    Context.TELECOM_SERVICE
                ) as TelecomManager

            if (
                Build.VERSION.SDK_INT >=
                Build.VERSION_CODES.P
            ) {

                if (
                    ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.ANSWER_PHONE_CALLS
                    ) != PackageManager.PERMISSION_GRANTED
                ) {

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

            telecom.endCall()

            println(
                "🔴 [TELECOM] Call ended"
            )

            true

        } catch (e: Exception) {

            println(
                "❌ End call failed: " +
                        e.message
            )

            false
        }
    }

    // ============================================================
    // AI AUDIO MODE
    // ============================================================

    private fun applyAiAudioMode() {

        try {

            val audio =
                getSystemService(
                    Context.AUDIO_SERVICE
                ) as AudioManager

            audio.mode =
                AudioManager.MODE_IN_CALL

            audio.isSpeakerphoneOn = false

            audio.isMicrophoneMute = false

            val maxVolume =
                audio.getStreamMaxVolume(
                    AudioManager.STREAM_VOICE_CALL
                )

            audio.setStreamVolume(
                AudioManager.STREAM_VOICE_CALL,
                maxVolume,
                0
            )

            println(
                "🔊 AI audio mode enabled"
            )

        } catch (e: Exception) {

            println(
                "⚠️ AI audio mode error: " +
                        e.message
            )
        }
    }

    // ============================================================
    // NORMAL AUDIO
    // ============================================================

    private fun restoreNormalAudio() {

        try {

            val audio =
                getSystemService(
                    Context.AUDIO_SERVICE
                ) as AudioManager

            audio.mode =
                AudioManager.MODE_IN_CALL

            audio.isMicrophoneMute = false

            val maxVolume =
                audio.getStreamMaxVolume(
                    AudioManager.STREAM_VOICE_CALL
                )

            audio.setStreamVolume(
                AudioManager.STREAM_VOICE_CALL,
                maxVolume / 2,
                0
            )

        } catch (e: Exception) {

            println(
                "⚠️ Restore audio error: " +
                        e.message
            )
        }
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

        if (requestCode == 5001) {

            val isDialer =
                checkDialerRole()

            println(
                "☎️ Dialer role result = $isDialer"
            )

            methodChannel?.invokeMethod(
                "dialerRoleChanged",
                isDialer
            )
        }
    }

    // ============================================================
    // CLEANUP
    // ============================================================

    override fun onDestroy() {

        callStateReceiver?.let {

            try {

                unregisterReceiver(it)

            } catch (_: Exception) {
            }
        }

        methodChannel = null

        super.onDestroy()
    }
}
