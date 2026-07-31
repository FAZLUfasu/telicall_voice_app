import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class VoiceService {
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();

  WebSocketChannel? _channel;
  bool _isConnected = false;

  Function(String token)? onTokenReceived;
  Function(String sender, String text)? onTranscriptReceived;
  Function(bool isConnected)? onStateChanged;

  bool get isConnected => _isConnected;

  void sendAudioChunk(Uint8List pcmBytes) {
    if (_isConnected && _channel != null) {
      try {
        _channel!.sink.add(pcmBytes);
      } catch (e) {
        debugPrint("⚠️ Failed to send audio chunk: $e");
      }
    }
  }

  void connectToBackend(
    String serverIp,
    String clientNumber, {
    String? details,
  }) {
    if (_isConnected && _channel != null) return;

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

      _channel!.sink.add(
        jsonEncode({
          "client_phone_number": clientNumber,
          "lead_details": details ?? "",
        }),
      );

      _channel!.stream.listen(
        (message) {
          if (message is Uint8List) {
            // Audio bytes handled if needed
          } else if (message is String) {
            try {
              final Map<String, dynamic> data = jsonDecode(message);

              if (data['event'] == 'ai_token' || data['type'] == 'ai_token') {
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
        onError: (error) => disconnectSession(),
        onDone: () => disconnectSession(),
      );
    } catch (e) {
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
    onStateChanged?.call(false);
  }
}
