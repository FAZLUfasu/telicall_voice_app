// // // import 'dart:async';
// // // import 'dart:typed_data';
// // // import 'package:flutter/foundation.dart';
// // // import 'package:record/record.dart';
// // // import 'voice_service.dart';

// // // class AudioStreamService {
// // //   static final AudioStreamService _instance = AudioStreamService._internal();
// // //   factory AudioStreamService() => _instance;
// // //   AudioStreamService._internal();

// // //   final AudioRecorder _audioRecorder = AudioRecorder();
// // //   StreamSubscription<Uint8List>? _audioStreamSubscription;
// // //   bool _isRecording = false;

// // //   bool get isRecording => _isRecording;

// // //   Future<void> startAudioStreaming() async {
// // //     if (_isRecording) return;

// // //     try {
// // //       if (await _audioRecorder.hasPermission()) {
// // //         const RecordConfig config = RecordConfig(
// // //           encoder: AudioEncoder.pcm16bits,
// // //           sampleRate: 16000,
// // //           numChannels: 1,
// // //         );

// // //         final Stream<Uint8List> stream = await _audioRecorder.startStream(
// // //           config,
// // //         );
// // //         _isRecording = true;
// // //         debugPrint("🎙️ Microphone stream running. AI is listening...");

// // //         _audioStreamSubscription = stream.listen(
// // //           (Uint8List pcmChunk) {
// // //             if (VoiceService().isConnected) {
// // //               VoiceService().sendAudioChunk(pcmChunk);
// // //             }
// // //           },
// // //           onError: (error) {
// // //             debugPrint("❌ Audio Stream Error: $error");
// // //             stopAudioStreaming();
// // //           },
// // //           onDone: () => stopAudioStreaming(),
// // //         );
// // //       }
// // //     } catch (e) {
// // //       debugPrint("❌ Failed to start audio recorder stream: $e");
// // //       stopAudioStreaming();
// // //     }
// // //   }

// // //   Future<void> stopAudioStreaming() async {
// // //     if (!_isRecording) return;

// // //     try {
// // //       await _audioStreamSubscription?.cancel();
// // //       _audioStreamSubscription = null;
// // //       await _audioRecorder.stop();
// // //     } catch (e) {
// // //       debugPrint("⚠️ Error stopping recorder: $e");
// // //     } finally {
// // //       _isRecording = false;
// // //       debugPrint("🧹 Audio Stream Stopped & Cleaned.");
// // //     }
// // //   }
// // // }

// // import 'dart:async';
// // import 'dart:typed_data';
// // import 'package:flutter/foundation.dart';
// // import 'package:record/record.dart';
// // import 'voice_service.dart';

// // class AudioStreamService {
// //   static final AudioStreamService _instance = AudioStreamService._internal();
// //   factory AudioStreamService() => _instance;
// //   AudioStreamService._internal();

// //   final AudioRecorder _audioRecorder = AudioRecorder();
// //   StreamSubscription<Uint8List>? _audioStreamSubscription;
// //   bool _isRecording = false;

// //   bool get isRecording => _isRecording;

// //   Future<void> startAudioStreaming() async {
// //     if (_isRecording) return;

// //     try {
// //       if (await _audioRecorder.hasPermission()) {
// //         // 🔑 CRITICAL: Disable manageAudioFocus to keep cellular calls active!
// //         const RecordConfig config = RecordConfig(
// //           encoder: AudioEncoder.pcm16bits,
// //           sampleRate: 16000,
// //           numChannels: 1,
// //           androidConfig: AndroidRecordConfig(
// //             // Prevents recording service from taking audio focus away from active calls
// //             useLegacy: false,
// //           ),
// //         );
// //         ;

// //         final Stream<Uint8List> stream = await _audioRecorder.startStream(
// //           config,
// //         );
// //         _isRecording = true;
// //         debugPrint("🎙️ Microphone stream running. AI is listening...");

// //         _audioStreamSubscription = stream.listen(
// //           (Uint8List pcmChunk) {
// //             if (VoiceService().isConnected) {
// //               VoiceService().sendAudioChunk(pcmChunk);
// //             }
// //           },
// //           onError: (error) {
// //             debugPrint("❌ Audio Stream Error: $error");
// //             stopAudioStreaming();
// //           },
// //           onDone: () => stopAudioStreaming(),
// //         );
// //       }
// //     } catch (e) {
// //       debugPrint("❌ Failed to start audio recorder stream: $e");
// //       stopAudioStreaming();
// //     }
// //   }

// //   Future<void> stopAudioStreaming() async {
// //     if (!_isRecording) return;

// //     try {
// //       await _audioStreamSubscription?.cancel();
// //       _audioStreamSubscription = null;
// //       await _audioRecorder.stop();
// //     } catch (e) {
// //       debugPrint("⚠️ Error stopping recorder: $e");
// //     } finally {
// //       _isRecording = false;
// //       debugPrint("🧹 Audio Stream Stopped & Cleaned.");
// //     }
// //   }
// // }

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'voice_service.dart';

class AudioStreamService {
  static final AudioStreamService _instance = AudioStreamService._internal();
  factory AudioStreamService() => _instance;
  AudioStreamService._internal();

  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioStreamSubscription;
  bool _isRecording = false;

  bool get isRecording => _isRecording;

  Future<void> startAudioStreaming() async {
    if (_isRecording) return;

    try {
      if (await _audioRecorder.hasPermission()) {
        // Keeps cellular active without audio focus takeover
        const RecordConfig config = RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          androidConfig: AndroidRecordConfig(useLegacy: false),
        );

        final Stream<Uint8List> stream = await _audioRecorder.startStream(
          config,
        );
        _isRecording = true;
        debugPrint("🎙️ Microphone stream running. AI is listening...");

        _audioStreamSubscription = stream.listen(
          (Uint8List pcmChunk) {
            if (VoiceService().isConnected) {
              VoiceService().sendAudioChunk(pcmChunk);
            }
          },
          onError: (error) {
            debugPrint("❌ Audio Stream Error: $error");
            stopAudioStreaming();
          },
          onDone: () => stopAudioStreaming(),
        );
      }
    } catch (e) {
      debugPrint("❌ Failed to start audio recorder stream: $e");
      stopAudioStreaming();
    }
  }

  Future<void> stopAudioStreaming() async {
    if (!_isRecording) return;

    try {
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;
      await _audioRecorder.stop();
    } catch (e) {
      debugPrint("⚠️ Error stopping recorder: $e");
    } finally {
      _isRecording = false;
      debugPrint("🧹 Audio Stream Stopped & Cleaned.");
    }
  }
}
