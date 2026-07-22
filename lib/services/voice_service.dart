import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:audioplayers/audioplayers.dart';

class VoiceService {
  // Pure Singleton instantiation
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();

  WebSocketChannel? _channel;
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  // Callback to notify the UI when the connection state shifts
  Function(bool)? onStateChanged;

  Future<bool> connect(String url) async {
    if (_isConnected || _channel != null) {
      debugPrint(
        "🌐 VoiceService: Channel already running. Blocking duplicate request.",
      );
      return true;
    }

    final completer = Completer<bool>();
    debugPrint(
      "🌐 VoiceService: Opening single clean pipeline socket to: $url",
    );

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));

      _channel!.stream.listen(
        (message) {
          if (!_isConnected) {
            _isConnected = true;
            onStateChanged?.call(true);
            debugPrint("✅ VoiceService: Pipeline Handshake Accepted!");
            completer.complete(true);
          }

          // Directly route incoming neural audio data chunks to the player hardware
          if (message is Uint8List) {
            _audioPlayer.play(BytesSource(message));
          }
        },
        onError: (err) {
          debugPrint("❌ VoiceService: Network stream encountered error: $err");
          if (!completer.isCompleted) completer.complete(false);
          disconnect();
        },
        onDone: () {
          debugPrint(
            "🔌 VoiceService: Remote host dropped channel connection.",
          );
          disconnect();
        },
      );
    } catch (e) {
      debugPrint("⚠️ VoiceService: Structural initialization crash: $e");
      if (!completer.isCompleted) completer.complete(false);
      disconnect();
    }

    return completer.future;
  }

  void sendInitialMetadata(String payload) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(payload);
    }
  }

  void sendAudioChunk(Uint8List chunk) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(chunk);
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _audioPlayer.stop();
    onStateChanged?.call(false);
    debugPrint(
      "🧹 VoiceService: Core variables cleaned and resources released.",
    );
  }
}
