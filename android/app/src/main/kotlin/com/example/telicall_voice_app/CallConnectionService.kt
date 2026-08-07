package com.example.telicall_voice_app

import android.telecom.TelecomManager
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.DisconnectCause
import android.telecom.PhoneAccountHandle
import android.util.Log

class CallConnectionService : ConnectionService() {

    companion object {
        private const val TAG = "CallConnectionService"
    }

    override fun onCreateOutgoingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle,
        request: ConnectionRequest
    ): Connection {

        Log.i(TAG, "📞 =================================")
        Log.i(TAG, "📞 CREATE OUTGOING CONNECTION")
        Log.i(TAG, "📞 Address: ${request.address}")
        Log.i(TAG, "📞 =================================")

        return try {

            val connection = TelicallConnection(
                isIncoming = false,
                request = request
            )

            request.address?.let {
                connection.setAddress(
                    it,
                    android.telecom.TelecomManager.PRESENTATION_ALLOWED
                )
            }

            connection.setInitializing()

            Log.i(TAG, "✅ Outgoing Connection created")

            connection

        } catch (e: Exception) {

            Log.e(
                TAG,
                "❌ Failed to create outgoing connection",
                e
            )

            Connection.createFailedConnection(
                DisconnectCause(
                    DisconnectCause.ERROR,
                    e.message ?: "Outgoing connection failed"
                )
            )
        }
    }

    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle,
        request: ConnectionRequest
    ): Connection {

        Log.i(TAG, "📞 =================================")
        Log.i(TAG, "📞 CREATE INCOMING CONNECTION")
        Log.i(TAG, "📞 Address: ${request.address}")
        Log.i(TAG, "📞 =================================")

        return try {

            val connection = TelicallConnection(
                isIncoming = true,
                request = request
            )
            
            request.address?.let {
                connection.setAddress(
                    it,
                    TelecomManager.PRESENTATION_ALLOWED
                )
            }

            connection.setInitializing()

            Log.i(TAG, "✅ Incoming Connection created")

            connection

        } catch (e: Exception) {

            Log.e(
                TAG,
                "❌ Failed to create incoming connection",
                e
            )

            Connection.createFailedConnection(
                DisconnectCause(
                    DisconnectCause.ERROR,
                    e.message ?: "Incoming connection failed"
                )
            )
        }
    }

    override fun onCreateOutgoingConnectionFailed(
        connectionManagerPhoneAccount: PhoneAccountHandle,
        request: ConnectionRequest
    ) {

        Log.e(
            TAG,
            "❌ Telecom outgoing connection failed: ${request.address}"
        )

        super.onCreateOutgoingConnectionFailed(
            connectionManagerPhoneAccount,
            request
        )
    }

    override fun onCreateIncomingConnectionFailed(
        connectionManagerPhoneAccount: PhoneAccountHandle,
        request: ConnectionRequest
    ) {

        Log.e(
            TAG,
            "❌ Telecom incoming connection failed: ${request.address}"
        )

        super.onCreateIncomingConnectionFailed(
            connectionManagerPhoneAccount,
            request
        )
    }

    private class TelicallConnection(
        private val isIncoming: Boolean,
        private val request: ConnectionRequest
    ) : Connection() {

        companion object {
            private const val TAG = "TelicallConnection"
        }

        
        init {

            Log.i(
                TAG,
                "📞 TelicallConnection initialized " +
                        "(incoming=$isIncoming)"
            )

            request.address?.let { address ->

                setAddress(
                    address,
                    TelecomManager.PRESENTATION_ALLOWED
                )
            }

            setConnectionCapabilities(
                Connection.CAPABILITY_HOLD or
                        Connection.CAPABILITY_MUTE
            )
        }

        override fun onAnswer() {

            Log.i(TAG, "🟢 =================================")
            Log.i(TAG, "🟢 CONNECTION ANSWERED")
            Log.i(TAG, "🟢 =================================")

            setActive()
        }

        override fun onReject() {

            Log.i(
                TAG,
                "❌ CONNECTION REJECTED"
            )

            setDisconnected(
                DisconnectCause(
                    DisconnectCause.REJECTED
                )
            )

            destroy()
        }

        override fun onDisconnect() {

            Log.i(
                TAG,
                "🔴 CONNECTION DISCONNECT REQUEST"
            )

            setDisconnected(
                DisconnectCause(
                    DisconnectCause.LOCAL
                )
            )

            destroy()
        }

        override fun onHold() {

            Log.i(
                TAG,
                "⏸ CONNECTION HOLD"
            )

            setOnHold()
        }

        override fun onUnhold() {

            Log.i(
                TAG,
                "▶️ CONNECTION UNHOLD"
            )

            setActive()
        }

        override fun onAbort() {

            Log.i(
                TAG,
                "🛑 CONNECTION ABORT"
            )

            setDisconnected(
                DisconnectCause(
                    DisconnectCause.CANCELED
                )
            )

            destroy()
        }
    }
}
