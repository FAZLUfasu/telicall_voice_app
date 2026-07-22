package com.example.telicall_voice_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.TelephonyManager

class CallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        // FIXED: Using standard intent action string comparison to bypass compile constraints
        if (intent?.action == "android.intent.action.PHONE_STATE") {
            val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE)
            println("📞 [NATIVE CALL STATE CHANGED]: $state")
        }
    }
}