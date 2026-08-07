// import 'dart:convert';
// import 'dart:typed_data';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/services.dart';
// import 'package:web_socket_channel/web_socket_channel.dart';

// class CallWebSocketService {
//   static const MethodChannel _platform = MethodChannel(
//     'com.example.telicall_voice_app/telecom',
//   );

//   WebSocketChannel? _channel;
//   bool _isConnected = false;

//   bool get isConnected => _isConnected;

//   /// Connect to the backend WebSocket media-stream server
//   void connect(String wsUrl) {
//     if (_isConnected) return;

//     try {
//       debugPrint("🔌 Connecting CallWebSocketService to $wsUrl");
//       _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
//       _isConnected = true;

//       _channel!.stream.listen(
//         (dynamic message) {
//           if (message is Uint8List) {
//             onReceiveTtsAudioChunk(message);
//           } else if (message is List<int>) {
//             final pcmBytes = Uint8List.fromList(message);
//             onReceiveTtsAudioChunk(pcmBytes);
//           } else if (message is String) {
//             try {
//               final Map<String, dynamic> data = jsonDecode(message);

//               if (data['event'] == 'audio' && data['pcm_base64'] != null) {
//                 final Uint8List pcmBytes = base64Decode(data['pcm_base64']);
//                 onReceiveTtsAudioChunk(pcmBytes);
//               }
//             } catch (e) {
//               debugPrint("⚠️ Error parsing JSON audio packet: $e");
//             }
//           }
//         },
//         onError: (error) {
//           debugPrint("❌ CallWebSocketService Error: $error");
//           disconnect();
//         },
//         onDone: () {
//           debugPrint("🔌 CallWebSocketService Session Closed.");
//           disconnect();
//         },
//       );
//     } catch (e) {
//       debugPrint("❌ WebSocket Connection Exception: $e");
//       disconnect();
//     }
//   }

//   /// Forwards incoming TTS PCM chunks to the native Android audio injector
//   void onReceiveTtsAudioChunk(Uint8List pcmChunk) async {
//     if (pcmChunk.isEmpty) return;

//     try {
//       await _platform.invokeMethod('playAiAudioChunk', {'pcmData': pcmChunk});
//     } on PlatformException catch (e) {
//       debugPrint("❌ Failed to inject audio chunk to platform: ${e.message}");
//     }
//   }

//   /// Sends raw audio bytes captured from the caller's mic stream back to the server
//   void sendCallerAudioChunk(Uint8List pcmChunk) {
//     if (_isConnected && _channel != null) {
//       try {
//         _channel!.sink.add(pcmChunk);
//       } catch (e) {
//         debugPrint("⚠️ Error sending audio chunk to WebSocket: $e");
//       }
//     }
//   }

//   /// Safely close the WebSocket connection and reset state
//   void disconnect() {
//     try {
//       _channel?.sink.close();
//     } catch (_) {}
//     _channel = null;
//     _isConnected = false;
//   }
// }
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class CallWebSocketService {
  static const MethodChannel _platform = MethodChannel(
    'com.example.telicall_voice_app/telecom',
  );

  WebSocketChannel? _channel;
  bool _isConnected = false;

  bool get isConnected => _isConnected;

  /// Connect to the backend WebSocket media-stream server
  void connect(String wsUrl) {
    if (_isConnected) return;

    try {
      debugPrint("🔌 Connecting CallWebSocketService to $wsUrl");
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isConnected = true;

      _channel!.stream.listen(
        (dynamic message) {
          if (message is Uint8List) {
            onReceiveTtsAudioChunk(message);
          } else if (message is List<int>) {
            final pcmBytes = Uint8List.fromList(message);
            onReceiveTtsAudioChunk(pcmBytes);
          } else if (message is String) {
            try {
              final Map<String, dynamic> data = jsonDecode(message);

              if (data['event'] == 'audio' && data['pcm_base64'] != null) {
                final Uint8List pcmBytes = base64Decode(data['pcm_base64']);
                onReceiveTtsAudioChunk(pcmBytes);
              }
            } catch (e) {
              debugPrint("⚠️ Error parsing JSON audio packet: $e");
            }
          }
        },
        onError: (error) {
          debugPrint("❌ CallWebSocketService Error: $error");
          disconnect();
        },
        onDone: () {
          debugPrint("🔌 CallWebSocketService Session Closed.");
          disconnect();
        },
      );
    } catch (e) {
      debugPrint("❌ WebSocket Connection Exception: $e");
      disconnect();
    }
  }

  /// Forwards incoming TTS PCM chunks to the native Android audio injector
  void onReceiveTtsAudioChunk(Uint8List pcmChunk) async {
    if (pcmChunk.isEmpty) return;

    try {
      await _platform.invokeMethod('playAiAudioChunk', {'pcmData': pcmChunk});
    } on PlatformException catch (e) {
      debugPrint("❌ Failed to inject audio chunk to platform: ${e.message}");
    }
  }

  /// Sends raw audio bytes captured from the caller's mic stream back to the server
  void sendCallerAudioChunk(Uint8List pcmChunk) {
    if (_isConnected && _channel != null) {
      try {
        _channel!.sink.add(pcmChunk);
      } catch (e) {
        debugPrint("⚠️ Error sending audio chunk to WebSocket: $e");
      }
    }
  }

  /// Safely close the WebSocket connection and reset state
  void disconnect() {
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _isConnected = false;
  }
}
