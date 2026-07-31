package com.example.telicall_voice_app

import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.telecom.TelecomManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.telicall_voice_app/telecom"
    private var isAiModeActive = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {

                // 📞 1. MAKE OUTBOUND PHONE CALL (Triggers Intent Once)
                "makeNativeInternalCall" -> {
                    val phoneNumber = call.argument<String>("phoneNumber")
                    isAiModeActive = call.argument<Boolean>("isAiMode") ?: false

                    if (!phoneNumber.isNullOrEmpty()) {
                        if (isAiModeActive) {
                            applyAiHardwareMute(audioManager)
                        } else {
                            restoreNormalAudio(audioManager)
                        }

                        val success = makeDirectCall(phoneNumber)
                        result.success(success)
                    } else {
                        result.error("INVALID_NUMBER", "Phone number is empty", null)
                    }
                }

                // 🔇 2. SET AUDIO MODE / MUTE ONLY (Does NOT launch call intent again)
                "setAudioMode" -> {
                    val isAiMode = call.argument<Boolean>("isAiMode") ?: false
                    isAiModeActive = isAiMode
                    if (isAiMode) {
                        applyAiHardwareMute(audioManager)
                    } else {
                        restoreNormalAudio(audioManager)
                    }
                    result.success(true)
                }

                // 🔴 3. DISCONNECT ACTIVE CALL
                "disconnectCall" -> {
                    isAiModeActive = false
                    restoreNormalAudio(audioManager)
                    val success = hangUpActiveCall()
                    result.success(success)
                }

                // 🔍 4. CHECK DEFAULT DIALER ROLE STATUS
                "checkDialerStatus" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val roleManager = getSystemService(Context.ROLE_SERVICE) as RoleManager
                        result.success(roleManager.isRoleHeld(RoleManager.ROLE_DIALER))
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
                        result.success(packageName == telecomManager.defaultDialerPackage)
                    } else {
                        result.success(false)
                    }
                }

                // ⚙️ 5. REQUEST DEFAULT DIALER ROLE
                "requestDefaultDialer", "requestDialerRole" -> {
                    requestDefaultDialerRole()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    /// 🚀 Launches the system direct phone call intent
    private fun makeDirectCall(number: String): Boolean {
    // 1. Ensure digits only with optional country code
    var cleanNum = number.replace("[^0-9+]".toRegex(), "")
    if (cleanNum.length == 10 && !cleanNum.startsWith("+")) {
        cleanNum = "+91$cleanNum"
    }

    val callUri = Uri.parse("tel:$cleanNum")

    return try {
        // 2. Direct Call Intent
        val intent = Intent(Intent.ACTION_CALL).apply {
            data = callUri
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }

        if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED) {
            startActivity(intent)
            println("📞 [NATIVE TELECOM]: Successfully launched direct call to $cleanNum")
            true
        } else {
            ActivityCompat.requestPermissions(this, arrayOf(android.Manifest.permission.CALL_PHONE), 1)
            false
        }
    } catch (e: Exception) {
        println("⚠️ [ACTION_CALL FAILED]: Opening system dialer window... (${e.message})")
        try {
            // 3. Fallback: Opens default System Dialer screen with prepopulated number
            val dialIntent = Intent(Intent.ACTION_DIAL, callUri).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(dialIntent)
            true
        } catch (dialException: Exception) {
            println("❌ [DIALER ERROR]: ${dialException.message}")
            false
        }
    }
}
    /// 🔴 Ends active phone call programmatically
    private fun hangUpActiveCall(): Boolean {
        return try {
            val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.ANSWER_PHONE_CALLS) == PackageManager.PERMISSION_GRANTED) {
                    telecomManager.endCall()
                    println("🔴 [NATIVE TELECOM]: Active call disconnected successfully.")
                    true
                } else {
                    ActivityCompat.requestPermissions(this, arrayOf(android.Manifest.permission.ANSWER_PHONE_CALLS), 2)
                    false
                }
            } else {
                @Suppress("DEPRECATION")
                telecomManager.endCall()
                true
            }
        } catch (e: Exception) {
            println("❌ [NATIVE TELECOM HANGUP ERROR]: ${e.message}")
            false
        }
    }

    /// ⚙️ Prompts user for system Default Dialer role
    private fun requestDefaultDialerRole() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roleManager = getSystemService(Context.ROLE_SERVICE) as RoleManager
            if (roleManager.isRoleAvailable(RoleManager.ROLE_DIALER) && !roleManager.isRoleHeld(RoleManager.ROLE_DIALER)) {
                val intent = roleManager.createRequestRoleIntent(RoleManager.ROLE_DIALER)
                startActivity(intent)
            }
        } else {
            try {
                val intent = Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
            } catch (e: Exception) {
                println("⚠️ Settings intent failed: ${e.message}")
            }
        }
    }

    /// 🔇 Mutes local hardware microphone and sets voice call volume to zero for AI mode
   private fun applyAiHardwareMute(audioManager: AudioManager) {
    try {
        // Use MODE_IN_COMMUNICATION so VoIP/AI audio and telecom coexist
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        
        // Do NOT set volume to 0 (which terminates carrier calls on MIUI/Samsung)
        // Keep volume at minimum 1 or manage via stream mute
        val minVol = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            audioManager.getStreamMinVolume(AudioManager.STREAM_VOICE_CALL)
        } else {
            1
        }
        audioManager.setStreamVolume(AudioManager.STREAM_VOICE_CALL, minVol, 0)
    } catch (e: Exception) {
        println("⚠️ Audio Mute Warning: ${e.message}")
    }
}

    /// 🔊 Restores normal voice call audio volume
    private fun restoreNormalAudio(audioManager: AudioManager) {
        try {
            audioManager.mode = AudioManager.MODE_NORMAL
            audioManager.isMicrophoneMute = false
            val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)
            audioManager.setStreamVolume(AudioManager.STREAM_VOICE_CALL, maxVol / 2, 0)
        } catch (e: Exception) {
            println("⚠️ Restore Audio Exception: ${e.message}")
        }
    }
}