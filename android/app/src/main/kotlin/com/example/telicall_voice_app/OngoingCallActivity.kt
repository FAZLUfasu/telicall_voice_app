package com.example.telicall_voice_app

import android.os.Bundle
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.embedding.android.FlutterActivity

class OngoingCallActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Simple fallback system placeholder view layout if launched outside Flutter framework directly
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = android.view.Gravity.CENTER
            setBackgroundColor(0xFF0F172A.toInt())
        }
        
        val text = TextView(this).apply {
            text = "Active Standalone Call Connected via Telicall"
            textSize = 20f
            setTextColor(0xFFFFFFFF.toInt())
        }
        
        layout.addView(text)
        setContentView(layout)
    }
}