package com.example.telicall_voice_app

import android.telecom.Call
import android.telecom.InCallService
import android.util.Log

class MyInCallService : InCallService() {

    override fun onCallAdded(call: Call) {
        super.onCallAdded(call)
        Log.d("InCallService", "📞 Call added: ${call.details.handle}")

        call.registerCallback(object : Call.Callback() {
            override fun onStateChanged(call: Call, state: Int) {
                super.onStateChanged(call, state)
                Log.d("InCallService", "📞 Call state changed: $state")
            }
        })
    }

    override fun onCallRemoved(call: Call) {
        super.onCallRemoved(call)
        Log.d("InCallService", "🔌 Call removed/ended.")
    }
}