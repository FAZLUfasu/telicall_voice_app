package com.example.telicall_voice_app

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.telecom.TelecomManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.telicall_voice_app/telecom"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "makeNativeInternalCall" -> {
                    val phoneNumber = call.argument<String>("phoneNumber")
                    if (!phoneNumber.isNullOrEmpty()) {
                        makeDirectCall(phoneNumber)
                        result.success(true)
                    } else {
                        result.error("INVALID_NUMBER", "Phone number is empty", null)
                    }
                }
                "disconnectCall" -> {
                    val success = hangUpActiveCall()
                    result.success(success)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun makeDirectCall(number: String) {
        val intent = Intent(Intent.ACTION_CALL).apply {
            data = Uri.parse("tel:$number")
        }
        if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED) {
            startActivity(intent)
        } else {
            ActivityCompat.requestPermissions(this, arrayOf(android.Manifest.permission.CALL_PHONE), 1)
        }
    }

    private fun hangUpActiveCall(): Boolean {
        return try {
            val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.ANSWER_PHONE_CALLS) == PackageManager.PERMISSION_GRANTED) {
                    telecomManager.endCall()
                    println("🔴 [NATIVE TELECOM]: Active call ended successfully.")
                    true
                } else {
                    ActivityCompat.requestPermissions(this, arrayOf(android.Manifest.permission.ANSWER_PHONE_CALLS), 2)
                    println("⚠️ [NATIVE TELECOM]: Permission ANSWER_PHONE_CALLS not granted.")
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
}