import 'package:flutter/foundation.dart';

class AudioStreamService {
  static final AudioStreamService _instance = AudioStreamService._internal();

  factory AudioStreamService() => _instance;

  AudioStreamService._internal();

  bool _isStreaming = false;

  bool get isRecording => _isStreaming;

  /// Starts the customer-audio pipeline.
  ///
  /// IMPORTANT:
  /// This does NOT start the Flutter microphone.
  ///
  /// Customer PCM is captured natively by Android using
  /// MediaRecorder.AudioSource.VOICE_DOWNLINK.
  ///
  /// Android then sends the PCM to VoiceService through:
  ///
  /// onCustomerDownlinkAudioReceived
  Future<void> startAudioStreaming() async {
    if (_isStreaming) {
      debugPrint("ℹ️ Customer downlink streaming already active.");
      return;
    }

    _isStreaming = true;

    debugPrint("==========================================");
    debugPrint("🎧 CUSTOMER AUDIO STREAM ACTIVE");
    debugPrint("✅ Source: Android VOICE_DOWNLINK");
    debugPrint("🚫 Flutter microphone capture: DISABLED");
    debugPrint("🌐 PCM will be sent through VoiceService");
    debugPrint("==========================================");
  }

  /// Stops the Flutter-side streaming state.
  ///
  /// The actual VOICE_DOWNLINK AudioRecord is stopped
  /// by AppInCallService when the cellular call ends.
  Future<void> stopAudioStreaming() async {
    if (!_isStreaming) {
      return;
    }

    _isStreaming = false;

    debugPrint("==========================================");
    debugPrint("🛑 CUSTOMER AUDIO STREAM STOPPED");
    debugPrint("🚫 No Flutter microphone recorder running");
    debugPrint("==========================================");
  }

  void reset() {
    _isStreaming = false;

    debugPrint("🧹 AudioStreamService reset.");
  }
}
