package com.example.telicall_voice_app

import android.os.Build
import android.telecom.Call
import android.telecom.InCallService
import androidx.annotation.RequiresApi

@RequiresApi(Build.VERSION_CODES.M)
class AppInCallService : InCallService() {
    
    override fun onCallAdded(call: Call?) {
        super.onCallAdded(call)
        // Monitors ongoing active loops natively
        println("📞 [TELICALL SYSTEM]: Hardware Call Active via InCallService")
    }

    override fun onCallRemoved(call: Call?) {
        super.onCallRemoved(call)
        println("📞 [TELICALL SYSTEM]: Hardware Call Disconnected")
    }
}