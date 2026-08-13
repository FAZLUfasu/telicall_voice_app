// import 'dart:io';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:audioplayers/audioplayers.dart';

// class AudioInspectorScreen extends StatefulWidget {
//   const AudioInspectorScreen({Key? key}) : super(key: key);

//   @override
//   State<AudioInspectorScreen> createState() => _AudioInspectorScreenState();
// }

// class _AudioInspectorScreenState extends State<AudioInspectorScreen> {
//   static const MethodChannel _telecomChannel = MethodChannel(
//     'com.example.telicall_voice_app/telecom',
//   );

//   final AudioPlayer _audioPlayer = AudioPlayer();
//   List<String> _chunkPaths = [];
//   String? _currentlyPlayingPath;
//   bool _isPlaying = false;

//   @override
//   void initState() {
//     super.initState();
//     _loadChunkFiles();

//     // Listen for real-time newly saved audio chunks from Android
//     _telecomChannel.setMethodCallHandler((call) async {
//       if (call.method == 'onNewChunkSaved') {
//         final String newPath = call.arguments.toString();
//         setState(() {
//           if (!_chunkPaths.contains(newPath)) {
//             _chunkPaths.add(newPath);
//           }
//         });
//       }
//     });

//     _audioPlayer.onPlayerStateChanged.listen((state) {
//       setState(() {
//         _isPlaying = state == PlayerState.playing;
//       });
//     });
//   }

//   Future<void> _loadChunkFiles() async {
//     try {
//       final List<dynamic> result = await _telecomChannel.invokeMethod(
//         'getRecordedChunks',
//       );
//       setState(() {
//         _chunkPaths = result.map((e) => e.toString()).toList();
//       });
//     } catch (e) {
//       debugPrint("Error loading chunks: $e");
//     }
//   }

//   Future<void> _clearChunks() async {
//     try {
//       await _audioPlayer.stop();
//       await _telecomChannel.invokeMethod('clearRecordedChunks');
//       setState(() {
//         _chunkPaths.clear();
//         _currentlyPlayingPath = null;
//       });
//     } catch (e) {
//       debugPrint("Error clearing chunks: $e");
//     }
//   }

//   Future<void> _playChunk(String path) async {
//     if (_currentlyPlayingPath == path && _isPlaying) {
//       await _audioPlayer.pause();
//     } else {
//       await _audioPlayer.stop();
//       await _audioPlayer.play(DeviceFileSource(path));
//       setState(() {
//         _currentlyPlayingPath = path;
//       });
//     }
//   }

//   @override
//   void dispose() {
//     _audioPlayer.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text("Customer Audio Inspector"),
//         backgroundColor: Colors.indigo,
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.delete_forever),
//             onPressed: _clearChunks,
//             tooltip: "Clear All Chunks",
//           ),
//           IconButton(
//             icon: const Icon(Icons.refresh),
//             onPressed: _loadChunkFiles,
//             tooltip: "Refresh List",
//           ),
//         ],
//       ),
//       body: _chunkPaths.isEmpty
//           ? const Center(
//               child: Text(
//                 "No captured call audio chunks found.\nPlace a call to start recording customer downlink.",
//                 textAlign: TextAlign.center,
//                 style: TextStyle(fontSize: 16, color: Colors.grey),
//               ),
//             )
//           : ListView.builder(
//               itemCount: _chunkPaths.length,
//               itemBuilder: (context, index) {
//                 final filePath = _chunkPaths[index];
//                 final fileName = filePath.split(Platform.pathSeparator).last;
//                 final isSelected = _currentlyPlayingPath == filePath;

//                 return Card(
//                   margin: const EdgeInsets.symmetric(
//                     horizontal: 12,
//                     vertical: 6,
//                   ),
//                   color: isSelected ? Colors.indigo.shade50 : Colors.white,
//                   child: ListTile(
//                     leading: CircleAvatar(
//                       backgroundColor: isSelected
//                           ? Colors.indigo
//                           : Colors.grey.shade300,
//                       child: Icon(
//                         isSelected && _isPlaying
//                             ? Icons.pause
//                             : Icons.play_arrow,
//                         color: isSelected ? Colors.white : Colors.black,
//                       ),
//                     ),
//                     title: Text(
//                       fileName,
//                       style: const TextStyle(fontWeight: FontWeight.bold),
//                     ),
//                     subtitle: Text(filePath, overflow: TextOverflow.ellipsis),
//                     trailing: IconButton(
//                       icon: Icon(
//                         isSelected && _isPlaying
//                             ? Icons.pause_circle_filled
//                             : Icons.play_circle_fill,
//                         color: Colors.indigo,
//                         size: 36,
//                       ),
//                       onPressed: () => _playChunk(filePath),
//                     ),
//                   ),
//                 );
//               },
//             ),
//     );
//   }
// }

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';

class AudioInspectorScreen extends StatefulWidget {
  const AudioInspectorScreen({Key? key}) : super(key: key);

  @override
  State<AudioInspectorScreen> createState() => _AudioInspectorScreenState();
}

class _AudioInspectorScreenState extends State<AudioInspectorScreen> {
  static const MethodChannel _telecomChannel = MethodChannel(
    'com.example.telicall_voice_app/telecom',
  );

  final AudioPlayer _audioPlayer = AudioPlayer();

  List<String> _chunkPaths = [];
  String? _currentlyPlayingPath;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();

    _loadChunkFiles();

    // Listen for real-time newly saved audio chunks from Android
    _telecomChannel.setMethodCallHandler((call) async {
      if (call.method == 'onNewChunkSaved') {
        final String newPath = call.arguments.toString();

        if (!mounted) return;

        setState(() {
          if (!_chunkPaths.contains(newPath)) {
            _chunkPaths.add(newPath);
          }
        });
      }
    });

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;

      setState(() {
        _isPlaying = state == PlayerState.playing;
      });
    });
  }

  // ============================================================
  // LOAD RECORDED FILES
  // ============================================================

  Future<void> _loadChunkFiles() async {
    try {
      final List<dynamic> result = await _telecomChannel.invokeMethod(
        'getRecordedChunks',
      );

      if (!mounted) return;

      setState(() {
        _chunkPaths = result.map((e) => e.toString()).toList();
      });
    } catch (e) {
      debugPrint("Error loading chunks: $e");
    }
  }

  // ============================================================
  // PLAY RECORDING
  // ============================================================

  Future<void> _playChunk(String path) async {
    try {
      final file = File(path);

      if (!await file.exists()) {
        _showMessage("File does not exist");
        return;
      }

      if (_currentlyPlayingPath == path && _isPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.stop();

        await _audioPlayer.play(DeviceFileSource(path));

        if (!mounted) return;

        setState(() {
          _currentlyPlayingPath = path;
        });
      }
    } catch (e) {
      debugPrint("Error playing file: $e");
      _showMessage("Unable to play recording");
    }
  }

  // ============================================================
  // SHARE RECORDING VIA SYSTEM SHEET
  // ============================================================

  Future<void> _shareRecording(String path) async {
    try {
      final file = File(path);

      if (!await file.exists()) {
        _showMessage("Recording file not found");
        return;
      }

      // Invoke native Android FileProvider / Intent share chooser
      await _telecomChannel.invokeMethod('shareRecordedChunk', {
        'filePath': path,
      });
    } catch (e) {
      debugPrint("❌ Error sharing recording: $e");
      _showMessage("Unable to open share menu");
    }
  }

  // ============================================================
  // CLEAR ALL RECORDINGS
  // ============================================================

  Future<void> _clearChunks() async {
    try {
      await _audioPlayer.stop();

      await _telecomChannel.invokeMethod('clearRecordedChunks');

      if (!mounted) return;

      setState(() {
        _chunkPaths.clear();
        _currentlyPlayingPath = null;
        _isPlaying = false;
      });
    } catch (e) {
      debugPrint("Error clearing chunks: $e");

      _showMessage("Unable to clear recordings");
    }
  }

  // ============================================================
  // MESSAGE HELPER
  // ============================================================

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ============================================================
  // BUILD UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Customer Audio Inspector"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          // CLEAR ALL
          IconButton(
            icon: const Icon(Icons.delete_forever),
            onPressed: _chunkPaths.isEmpty ? null : _clearChunks,
            tooltip: "Clear All Chunks",
          ),

          // REFRESH
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadChunkFiles,
            tooltip: "Refresh List",
          ),
        ],
      ),

      body: _chunkPaths.isEmpty
          ? const Center(
              child: Text(
                "No captured call audio chunks found.\n\n"
                "Place a call to start recording customer downlink.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _chunkPaths.length,
              itemBuilder: (context, index) {
                final filePath = _chunkPaths[index];
                final fileName = filePath.split(Platform.pathSeparator).last;
                final isSelected = _currentlyPlayingPath == filePath;

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  elevation: 2,
                  color: isSelected ? Colors.indigo.shade50 : Colors.white,

                  child: ListTile(
                    // LEFT ICON
                    leading: CircleAvatar(
                      backgroundColor: isSelected
                          ? Colors.indigo
                          : Colors.grey.shade300,
                      child: Icon(
                        isSelected && _isPlaying ? Icons.pause : Icons.mic,
                        color: isSelected ? Colors.white : Colors.black,
                      ),
                    ),

                    // FILE NAME
                    title: Text(
                      fileName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),

                    // FILE PATH
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        filePath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ),

                    // ACTIONS (PLAY & SHARE BUTTONS)
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // PLAY / PAUSE BUTTON
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(
                            isSelected && _isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_fill,
                            color: Colors.indigo,
                            size: 32,
                          ),
                          tooltip: "Play",
                          onPressed: () {
                            _playChunk(filePath);
                          },
                        ),
                        const SizedBox(width: 14),

                        // SHARE BUTTON (Triggers WhatsApp / Installed Apps)
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(
                            Icons.share,
                            color: Colors.green,
                            size: 26,
                          ),
                          tooltip: "Share File",
                          onPressed: () {
                            _shareRecording(filePath);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}
