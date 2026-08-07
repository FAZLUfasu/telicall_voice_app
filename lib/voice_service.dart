// import 'dart:async';
// import 'dart:convert';
// import 'dart:typed_data';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/services.dart';
// import 'package:web_socket_channel/web_socket_channel.dart';
// import 'call_web_socket_service.dart';

// class VoiceService {
//   static final VoiceService _instance = VoiceService._internal();
//   factory VoiceService() => _instance;
//   VoiceService._internal();

//   static const MethodChannel _telecomChannel = MethodChannel(
//     'com.example.telicall_voice_app/telecom',
//   );

//   WebSocketChannel? _channel;
//   bool _isConnected = false;
//   final CallWebSocketService _audioInjectorService = CallWebSocketService();

//   Function(String token)? onTokenReceived;
//   Function(String sender, String text)? onTranscriptReceived;
//   Function(bool isConnected)? onStateChanged;

//   bool get isConnected => _isConnected;

//   /// Call this during app startup or before placing a call to bind Native Platform Channel
//   void initializeNativeListeners() {
//     _telecomChannel.setMethodCallHandler((call) async {
//       switch (call.method) {
//         case 'onCallAnswered':
//           debugPrint(
//             "📞 Native [onCallAnswered] received! Triggering initial greeting.",
//           );
//           notifyCallAnswered();
//           break;

//         case 'onCallEnded':
//           debugPrint(
//             "🔌 Native [onCallEnded] received! Disconnecting WebSocket session.",
//           );
//           disconnectSession();
//           break;

//         case 'onCallerAudioReceived':
//           // Raw PCM bytes captured from active cellular downlink stream
//           if (call.arguments is Uint8List) {
//             final Uint8List pcmBytes = call.arguments as Uint8List;
//             sendAudioChunk(pcmBytes);
//           }
//           break;

//         default:
//           break;
//       }
//     });
//   }

//   void sendAudioChunk(Uint8List pcmBytes) {
//     if (_isConnected && _channel != null) {
//       try {
//         _channel!.sink.add(pcmBytes);
//       } catch (e) {
//         debugPrint("⚠️ Failed to send audio chunk: $e");
//       }
//     }
//   }

//   /// Sends call_answered event to backend to trigger the initial greeting
//   void notifyCallAnswered() {
//     if (_channel != null && _isConnected) {
//       try {
//         _channel!.sink.add(
//           jsonEncode({"event": "call_answered", "status": "ACTIVE"}),
//         );
//         debugPrint("✅ Sent 'call_answered' event to WebSocket server.");
//       } catch (e) {
//         debugPrint("⚠️ Failed to send call_answered event: $e");
//       }
//     }
//   }

//   void connectToBackend(
//     String serverIp,
//     String clientNumber, {
//     String? details,
//   }) {
//     if (_isConnected && _channel != null) return;

//     String cleanHost = serverIp.replaceAll(RegExp(r'^https?://|^wss?://'), '');
//     if (cleanHost.endsWith('/')) {
//       cleanHost = cleanHost.substring(0, cleanHost.length - 1);
//     }
//     if (!cleanHost.contains(':') && !cleanHost.contains('ngrok')) {
//       cleanHost = "$cleanHost:8000";
//     }

//     final String wsUrl = "ws://$cleanHost/ws/media-stream/";
//     debugPrint("🌐 VoiceService: Connecting to $wsUrl");

//     try {
//       _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
//       _isConnected = true;
//       onStateChanged?.call(true);

//       _channel!.sink.add(
//         jsonEncode({
//           "client_phone_number": clientNumber,
//           "lead_details": details ?? "",
//         }),
//       );

//       _channel!.stream.listen(
//         (message) {
//           if (message is Uint8List) {
//             _audioInjectorService.onReceiveTtsAudioChunk(message);
//           } else if (message is List<int>) {
//             _audioInjectorService.onReceiveTtsAudioChunk(
//               Uint8List.fromList(message),
//             );
//           } else if (message is String) {
//             try {
//               final Map<String, dynamic> data = jsonDecode(message);

//               if (data['event'] == 'audio' && data['pcm_base64'] != null) {
//                 final Uint8List pcmBytes = base64Decode(data['pcm_base64']);
//                 _audioInjectorService.onReceiveTtsAudioChunk(pcmBytes);
//               } else if (data['event'] == 'ai_token' ||
//                   data['type'] == 'ai_token') {
//                 final String token = data['text'] ?? data['token'] ?? '';
//                 if (token.isNotEmpty) {
//                   onTokenReceived?.call(token);
//                 }
//               } else if (data['type'] == 'user_transcript' ||
//                   data['event'] == 'user_transcript') {
//                 final String text = data['text'] ?? '';
//                 if (text.isNotEmpty) {
//                   onTranscriptReceived?.call("Customer", text);
//                 }
//               } else if (data['type'] == 'ai_response' ||
//                   data['event'] == 'ai_response') {
//                 final String text = data['text'] ?? '';
//                 if (text.isNotEmpty) {
//                   onTranscriptReceived?.call("AI", text);
//                 }
//               }
//             } catch (_) {
//               onTokenReceived?.call(message);
//             }
//           }
//         },
//         onError: (error) {
//           debugPrint("⚠️ WebSocket Error: $error");
//           disconnectSession();
//         },
//         onDone: () {
//           debugPrint("🔌 WebSocket Connection Closed.");
//           disconnectSession();
//         },
//       );
//     } catch (e) {
//       debugPrint("❌ Connection Exception: $e");
//       disconnectSession();
//     }
//   }

//   void syncHardwareCallState(String state) {
//     if (_channel != null && _isConnected) {
//       try {
//         _channel!.sink.add(
//           jsonEncode({"event": "call_state_changed", "state": state}),
//         );
//       } catch (_) {}
//     }
//   }

//   void disconnectSession() {
//     try {
//       _channel?.sink.close();
//     } catch (_) {}
//     _channel = null;
//     _isConnected = false;
//     onStateChanged?.call(false);
//   }
// }
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'call_web_socket_service.dart';

class VoiceService {
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();

  static const MethodChannel _telecomChannel = MethodChannel(
    'com.example.telicall_voice_app/telecom',
  );

  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _pendingCallAnswered =
      false; // 🚩 Guard flag for connection race conditions
  final CallWebSocketService _audioInjectorService = CallWebSocketService();

  Function(String token)? onTokenReceived;
  Function(String sender, String text)? onTranscriptReceived;
  Function(bool isConnected)? onStateChanged;

  bool get isConnected => _isConnected;

  /// Binds Platform Channel listeners for Native Android Telecom events
  void initializeNativeListeners() {
    _telecomChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onCallAnswered':
          debugPrint(
            "📞 Native [onCallAnswered] received! Triggering initial greeting...",
          );
          notifyCallAnswered();
          break;

        case 'onCallEnded':
          debugPrint(
            "🔌 Native [onCallEnded] received! Disconnecting WebSocket session.",
          );
          disconnectSession();
          break;

        case 'onCallerAudioReceived':
          // Raw PCM bytes captured from active cellular downlink stream
          if (_isConnected && call.arguments is Uint8List) {
            final Uint8List pcmBytes = call.arguments as Uint8List;
            sendAudioChunk(pcmBytes);
          }
          break;

        default:
          break;
      }
    });
  }

  /// Sends raw audio bytes captured from the caller's mic stream back to Django
  void sendAudioChunk(Uint8List pcmBytes) {
    if (_isConnected && _channel != null && pcmBytes.isNotEmpty) {
      try {
        _channel!.sink.add(pcmBytes);
      } catch (e) {
        debugPrint("⚠️ Failed to send audio chunk to WebSocket: $e");
      }
    }
  }

  /// Sends call_answered event to backend to trigger the initial opening greeting
  void notifyCallAnswered() {
    if (_channel != null && _isConnected) {
      try {
        _channel!.sink.add(
          jsonEncode({"event": "call_answered", "status": "ACTIVE"}),
        );
        _pendingCallAnswered = false;
        debugPrint("✅ Sent 'call_answered' event to WebSocket server.");
      } catch (e) {
        debugPrint("⚠️ Failed to send call_answered event: $e");
      }
    } else {
      // Buffer event if socket is still establishing
      debugPrint("⏳ Socket not ready yet. Queueing 'call_answered' event...");
      _pendingCallAnswered = true;
    }
  }

  /// Connects to the Django Channels WebSocket media stream endpoint
  void connectToBackend(
    String serverIp,
    String clientNumber, {
    String? details,
  }) {
    if (_isConnected && _channel != null) {
      disconnectSession();
    }

    String cleanHost = serverIp.replaceAll(RegExp(r'^https?://|^wss?://'), '');
    if (cleanHost.endsWith('/')) {
      cleanHost = cleanHost.substring(0, cleanHost.length - 1);
    }
    if (!cleanHost.contains(':') && !cleanHost.contains('ngrok')) {
      cleanHost = "$cleanHost:8000";
    }

    final String wsUrl = "ws://$cleanHost/ws/media-stream/";
    debugPrint("🌐 VoiceService: Connecting to $wsUrl");

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isConnected = true;
      onStateChanged?.call(true);

      // 1. Send initial call metadata upon connection
      _channel!.sink.add(
        jsonEncode({
          "client_phone_number": clientNumber,
          "lead_details": details ?? "",
        }),
      );

      // 2. Flush pending call_answered event if native event fired earlier
      if (_pendingCallAnswered) {
        notifyCallAnswered();
      }

      _channel!.stream.listen(
        (message) {
          if (message is Uint8List) {
            _audioInjectorService.onReceiveTtsAudioChunk(message);
          } else if (message is List<int>) {
            _audioInjectorService.onReceiveTtsAudioChunk(
              Uint8List.fromList(message),
            );
          } else if (message is String) {
            try {
              final Map<String, dynamic> data = jsonDecode(message);

              if (data['event'] == 'audio' && data['pcm_base64'] != null) {
                final Uint8List pcmBytes = base64Decode(data['pcm_base64']);
                _audioInjectorService.onReceiveTtsAudioChunk(pcmBytes);
              } else if (data['event'] == 'ai_token' ||
                  data['type'] == 'ai_token') {
                final String token = data['text'] ?? data['token'] ?? '';
                if (token.isNotEmpty) {
                  onTokenReceived?.call(token);
                }
              } else if (data['type'] == 'user_transcript' ||
                  data['event'] == 'user_transcript') {
                final String text = data['text'] ?? '';
                if (text.isNotEmpty) {
                  onTranscriptReceived?.call("Customer", text);
                }
              } else if (data['type'] == 'ai_response' ||
                  data['event'] == 'ai_response') {
                final String text = data['text'] ?? '';
                if (text.isNotEmpty) {
                  onTranscriptReceived?.call("AI", text);
                }
              }
            } catch (_) {
              onTokenReceived?.call(message);
            }
          }
        },
        onError: (error) {
          debugPrint("⚠️ WebSocket Error: $error");
          disconnectSession();
        },
        onDone: () {
          debugPrint("🔌 WebSocket Connection Closed.");
          disconnectSession();
        },
      );
    } catch (e) {
      debugPrint("❌ Connection Exception: $e");
      disconnectSession();
    }
  }

  void syncHardwareCallState(String state) {
    if (_channel != null && _isConnected) {
      try {
        _channel!.sink.add(
          jsonEncode({"event": "call_state_changed", "state": state}),
        );
      } catch (_) {}
    }
  }

  void disconnectSession() {
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _isConnected = false;
    _pendingCallAnswered = false;
    onStateChanged?.call(false);
  }
}
