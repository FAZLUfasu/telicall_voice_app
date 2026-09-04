import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class AiResponseWavSaver {
  AiResponseWavSaver._();

  static final AiResponseWavSaver instance = AiResponseWavSaver._();

  final List<int> _pcmBuffer = <int>[];
  int _chunkCount = 0;
  String? _lastSavedPath;

  String? get lastSavedPath => _lastSavedPath;
  int get bufferedBytes => _pcmBuffer.length;
  int get chunkCount => _chunkCount;

  /// Add raw PCM16LE, mono, 16 kHz audio received from Django.
  void appendPcm(Uint8List pcmBytes) {
    if (pcmBytes.isEmpty) return;

    _pcmBuffer.addAll(pcmBytes);
    _chunkCount++;

    print(
      '💾 [AI WAV BUFFER] chunk=$_chunkCount '
      'bytes=${pcmBytes.length} total=${_pcmBuffer.length}',
    );
  }

  /// Save all buffered AI PCM as a valid WAV file.
  Future<String?> saveSession({String prefix = 'ai_response_flutter'}) async {
    if (_pcmBuffer.isEmpty) {
      print('⚠️ [AI WAV SAVE] No AI PCM buffered.');
      return null;
    }

    try {
      final Directory baseDir = await getApplicationDocumentsDirectory();
      final Directory outputDir = Directory(
        '${baseDir.path}${Platform.pathSeparator}ai_response_recordings',
      );

      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      final int timestamp = DateTime.now().millisecondsSinceEpoch;
      final String filePath =
          '${outputDir.path}${Platform.pathSeparator}${prefix}_$timestamp.wav';

      Uint8List pcm = Uint8List.fromList(_pcmBuffer);

      // PCM16 requires an even number of bytes.
      if (pcm.length.isOdd) {
        pcm = pcm.sublist(0, pcm.length - 1);
      }

      final Uint8List wavBytes = _buildWav(
        pcm,
        sampleRate: 16000,
        channels: 1,
        bitsPerSample: 16,
      );

      final File wavFile = File(filePath);
      await wavFile.writeAsBytes(wavBytes, flush: true);

      _lastSavedPath = wavFile.path;

      print('==========================================');
      print('✅ [AI WAV SAVED IN FLUTTER]');
      print('📁 PATH: ${wavFile.path}');
      print('🎧 PCM bytes: ${pcm.length}');
      print('📦 WAV bytes: ${wavBytes.length}');
      print('🧩 AI chunks: $_chunkCount');
      print('==========================================');

      return wavFile.path;
    } catch (e, stackTrace) {
      print('❌ [AI WAV SAVE ERROR]: $e');
      print(stackTrace);
      return null;
    }
  }

  /// Save a single AI response chunk as its own WAV.
  Future<String?> saveSingleChunk(
    Uint8List pcmBytes, {
    String prefix = 'ai_chunk',
  }) async {
    if (pcmBytes.isEmpty) return null;

    try {
      final Directory baseDir = await getApplicationDocumentsDirectory();
      final Directory outputDir = Directory(
        '${baseDir.path}${Platform.pathSeparator}ai_response_recordings',
      );

      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      Uint8List pcm = pcmBytes;
      if (pcm.length.isOdd) {
        pcm = pcm.sublist(0, pcm.length - 1);
      }

      final int timestamp = DateTime.now().millisecondsSinceEpoch;
      final String filePath =
          '${outputDir.path}${Platform.pathSeparator}${prefix}_$timestamp.wav';

      final Uint8List wavBytes = _buildWav(
        pcm,
        sampleRate: 16000,
        channels: 1,
        bitsPerSample: 16,
      );

      final File wavFile = File(filePath);
      await wavFile.writeAsBytes(wavBytes, flush: true);

      print(
        '✅ [AI CHUNK WAV SAVED] '
        'pcm=${pcm.length} path=${wavFile.path}',
      );

      return wavFile.path;
    } catch (e, stackTrace) {
      print('❌ [AI CHUNK WAV SAVE ERROR]: $e');
      print(stackTrace);
      return null;
    }
  }

  void reset() {
    _pcmBuffer.clear();
    _chunkCount = 0;
    _lastSavedPath = null;

    print('🧹 [AI WAV BUFFER RESET]');
  }

  Uint8List _buildWav(
    Uint8List pcmBytes, {
    required int sampleRate,
    required int channels,
    required int bitsPerSample,
  }) {
    final int byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final int blockAlign = channels * bitsPerSample ~/ 8;
    final int dataLength = pcmBytes.length;
    final int fileLength = 36 + dataLength;

    final ByteData header = ByteData(44);

    void writeAscii(int offset, String value) {
      for (int i = 0; i < value.length; i++) {
        header.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    header.setUint32(4, fileLength, Endian.little);
    writeAscii(8, 'WAVE');

    writeAscii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little); // PCM fmt chunk size
    header.setUint16(20, 1, Endian.little); // PCM format
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);

    writeAscii(36, 'data');
    header.setUint32(40, dataLength, Endian.little);

    final BytesBuilder builder = BytesBuilder(copy: false);
    builder.add(header.buffer.asUint8List());
    builder.add(pcmBytes);

    return builder.takeBytes();
  }
}
