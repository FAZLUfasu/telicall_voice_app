package com.example.telicall_voice_app

import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.PhoneAccountHandle

class CallConnectionService : ConnectionService() {
    override fun onCreateOutgoingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ): Connection {
        val connection = object : Connection() {
            init {
                setConnectionProperties(PROPERTY_SELF_MANAGED)
                setAudioModeIsVoip(true)
            }
        }
        return connection
    }

    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ): Connection {
        val connection = object : Connection() {
            init {
                setConnectionProperties(PROPERTY_SELF_MANAGED)
                setAudioModeIsVoip(true)
            }
        }
        return connection
    }
}