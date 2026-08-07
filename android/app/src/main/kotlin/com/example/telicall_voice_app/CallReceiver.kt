package com.example.telicall_voice_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.TelephonyManager
import android.util.Log

class CallReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "CallReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {

        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) {
            return
        }

        val state = intent.getStringExtra(TelephonyManager.EXTRA_STATE)

        Log.d(TAG, "📞 Phone state changed: $state")

        when (state) {

            TelephonyManager.EXTRA_STATE_RINGING -> {
                val incomingNumber =
                    intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)

                Log.d(TAG, "📞 RINGING: $incomingNumber")
            }

            TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                Log.d(TAG, "📞 OFFHOOK - call connected")
            }

            TelephonyManager.EXTRA_STATE_IDLE -> {
                Log.d(TAG, "📞 IDLE - call ended")
            }
        }
    }
}