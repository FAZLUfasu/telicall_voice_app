import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class AiResponseInspectorScreen extends StatefulWidget {
  const AiResponseInspectorScreen({super.key});

  @override
  State<AiResponseInspectorScreen> createState() =>
      _AiResponseInspectorScreenState();
}

class _AiResponseInspectorScreenState extends State<AiResponseInspectorScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();

  List<String> _wavPaths = <String>[];

  String? _currentlyPlayingPath;
  bool _isPlaying = false;
  bool _isLoading = false;

  String? _recordingsDirectoryPath;

  @override
  void initState() {
    super.initState();

    _loadAiWavFiles();

    _audioPlayer.onPlayerStateChanged.listen((PlayerState state) {
      if (!mounted) return;

      setState(() {
        _isPlaying = state == PlayerState.playing;
      });
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;

      setState(() {
        _isPlaying = false;
        _currentlyPlayingPath = null;
      });

      debugPrint("✅ AI WAV playback completed");
    });
  }

  // ============================================================
  // GET AI WAV DIRECTORY
  // ============================================================

  Future<Directory> _getAiRecordingDirectory() async {
    final Directory appDocumentsDirectory =
        await getApplicationDocumentsDirectory();

    final Directory recordingsDirectory = Directory(
      '${appDocumentsDirectory.path}'
      '${Platform.pathSeparator}'
      'ai_response_recordings',
    );

    if (!await recordingsDirectory.exists()) {
      await recordingsDirectory.create(recursive: true);
    }

    _recordingsDirectoryPath = recordingsDirectory.path;

    return recordingsDirectory;
  }

  // ============================================================
  // LOAD AI WAV FILES
  // ============================================================

  Future<void> _loadAiWavFiles() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final Directory recordingsDirectory = await _getAiRecordingDirectory();

      final List<File> wavFiles = recordingsDirectory
          .listSync()
          .whereType<File>()
          .where((File file) => file.path.toLowerCase().endsWith('.wav'))
          .toList();

      wavFiles.sort((File a, File b) {
        try {
          return b.lastModifiedSync().compareTo(a.lastModifiedSync());
        } catch (_) {
          return 0;
        }
      });

      final List<String> paths = wavFiles
          .map((File file) => file.path)
          .toList();

      if (!mounted) return;

      setState(() {
        _wavPaths = paths;
        _isLoading = false;
      });

      debugPrint("==========================================");
      debugPrint("🎧 AI RESPONSE AUDIO INSPECTOR");
      debugPrint("📁 $_recordingsDirectoryPath");
      debugPrint("🎵 WAV files found: ${_wavPaths.length}");
      debugPrint("==========================================");
    } catch (e, stackTrace) {
      debugPrint("❌ Error loading AI WAV files: $e");
      debugPrint("$stackTrace");

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showMessage("Unable to load AI response recordings");
    }
  }

  // ============================================================
  // PLAY / PAUSE AI WAV
  // ============================================================

  Future<void> _playAiWav(String path) async {
    try {
      final File file = File(path);

      if (!await file.exists()) {
        _showMessage("AI WAV file does not exist");

        await _loadAiWavFiles();

        return;
      }

      debugPrint("==========================================");
      debugPrint("🎧 AI WAV PLAY REQUEST");
      debugPrint("📁 $path");
      debugPrint("📦 bytes=${await file.length()}");
      debugPrint("==========================================");

      // --------------------------------------------------------
      // CURRENT FILE PLAYING -> PAUSE
      // --------------------------------------------------------

      if (_currentlyPlayingPath == path && _isPlaying) {
        await _audioPlayer.pause();

        if (!mounted) return;

        setState(() {
          _isPlaying = false;
        });

        debugPrint("⏸️ AI WAV paused");

        return;
      }

      // --------------------------------------------------------
      // CURRENT FILE PAUSED -> RESUME
      // --------------------------------------------------------

      if (_currentlyPlayingPath == path && !_isPlaying) {
        await _audioPlayer.resume();

        if (!mounted) return;

        setState(() {
          _isPlaying = true;
        });

        debugPrint("▶️ AI WAV resumed");

        return;
      }

      // --------------------------------------------------------
      // DIFFERENT FILE -> STOP OLD + PLAY NEW
      // --------------------------------------------------------

      await _audioPlayer.stop();

      await _audioPlayer.play(DeviceFileSource(path));

      if (!mounted) return;

      setState(() {
        _currentlyPlayingPath = path;
        _isPlaying = true;
      });

      debugPrint("▶️ AI WAV playback started");
    } catch (e, stackTrace) {
      debugPrint("❌ Error playing AI WAV: $e");
      debugPrint("$stackTrace");

      if (!mounted) return;

      setState(() {
        _currentlyPlayingPath = null;
        _isPlaying = false;
      });

      _showMessage("Unable to play AI response recording");
    }
  }

  // ============================================================
  // DELETE ONE AI WAV FILE
  // ============================================================

  Future<void> _deleteAiWav(String path) async {
    try {
      if (_currentlyPlayingPath == path) {
        await _audioPlayer.stop();

        _currentlyPlayingPath = null;
        _isPlaying = false;
      }

      final File file = File(path);

      if (await file.exists()) {
        await file.delete();
      }

      if (!mounted) return;

      _showMessage("AI response WAV deleted");

      await _loadAiWavFiles();
    } catch (e) {
      debugPrint("❌ Error deleting AI WAV: $e");

      _showMessage("Unable to delete AI response recording");
    }
  }

  // ============================================================
  // CLEAR ALL AI WAV FILES
  // ============================================================

  Future<void> _clearAllAiWavs() async {
    try {
      await _audioPlayer.stop();

      final Directory recordingsDirectory = await _getAiRecordingDirectory();

      final List<FileSystemEntity> files = recordingsDirectory.listSync();

      for (final FileSystemEntity entity in files) {
        if (entity is File && entity.path.toLowerCase().endsWith('.wav')) {
          try {
            await entity.delete();
          } catch (e) {
            debugPrint("Unable to delete ${entity.path}: $e");
          }
        }
      }

      if (!mounted) return;

      setState(() {
        _wavPaths.clear();
        _currentlyPlayingPath = null;
        _isPlaying = false;
      });

      _showMessage("All AI response WAV files cleared");
    } catch (e) {
      debugPrint("❌ Error clearing AI WAV files: $e");

      _showMessage("Unable to clear AI response recordings");
    }
  }

  // ============================================================
  // CONFIRM CLEAR ALL
  // ============================================================

  Future<void> _confirmClearAll() async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Clear AI Recordings?"),
          content: const Text(
            "This will permanently delete all saved AI WAV files.",
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: const Text("Clear All"),
            ),
          ],
        );
      },
    );

    if (result == true) {
      await _clearAllAiWavs();
    }
  }

  // ============================================================
  // CONFIRM DELETE SINGLE FILE
  // ============================================================

  Future<void> _confirmDelete(String path) async {
    final String fileName = path.split(Platform.pathSeparator).last;

    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Delete AI Recording?"),
          content: Text(fileName),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: const Text("Delete"),
            ),
          ],
        );
      },
    );

    if (result == true) {
      await _deleteAiWav(path);
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
  // FILE SIZE
  // ============================================================

  String _getFileSize(String path) {
    try {
      final int bytes = File(path).lengthSync();

      if (bytes < 1024) {
        return "$bytes B";
      }

      final double kb = bytes / 1024;

      if (kb < 1024) {
        return "${kb.toStringAsFixed(1)} KB";
      }

      final double mb = kb / 1024;

      return "${mb.toStringAsFixed(2)} MB";
    } catch (_) {
      return "Unknown size";
    }
  }

  // ============================================================
  // BUILD UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AI Response Audio Inspector"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: <Widget>[
          // CLEAR ALL
          IconButton(
            icon: const Icon(Icons.delete_forever),
            onPressed: _wavPaths.isEmpty ? null : _confirmClearAll,
            tooltip: "Clear All AI Recordings",
          ),

          // REFRESH
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadAiWavFiles,
            tooltip: "Refresh List",
          ),
        ],
      ),

      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _wavPaths.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.graphic_eq, size: 70, color: Colors.grey),
                    const SizedBox(height: 18),
                    const Text(
                      "No AI response WAV files found.\n\n"
                      "Place a call and wait for the backend "
                      "to generate an AI response.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    if (_recordingsDirectoryPath != null) ...<Widget>[
                      const SizedBox(height: 20),
                      Text(
                        _recordingsDirectoryPath!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _wavPaths.length,
              itemBuilder: (BuildContext context, int index) {
                final String filePath = _wavPaths[index];

                final String fileName = filePath
                    .split(Platform.pathSeparator)
                    .last;

                final bool isSelected = _currentlyPlayingPath == filePath;

                final bool isSessionFile = fileName.startsWith(
                  "ai_flutter_session",
                );

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
                        isSelected && _isPlaying
                            ? Icons.pause
                            : isSessionFile
                            ? Icons.library_music
                            : Icons.smart_toy,
                        color: isSelected ? Colors.white : Colors.black,
                      ),
                    ),

                    // FILE NAME
                    title: Text(
                      fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),

                    // FILE PATH + SIZE
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            _getFileSize(filePath),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            filePath,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // PLAY + DELETE
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        // PLAY / PAUSE
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(
                            isSelected && _isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_fill,
                            color: Colors.indigo,
                            size: 34,
                          ),
                          tooltip: isSelected && _isPlaying ? "Pause" : "Play",
                          onPressed: () {
                            _playAiWav(filePath);
                          },
                        ),

                        const SizedBox(width: 14),

                        // DELETE
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                            size: 26,
                          ),
                          tooltip: "Delete WAV",
                          onPressed: () {
                            _confirmDelete(filePath);
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
