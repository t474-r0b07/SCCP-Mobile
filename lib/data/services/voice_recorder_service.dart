import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceRecorderService {
  VoiceRecorderService._();

  static final AudioRecorder _recorder = AudioRecorder();

  static Future<String?> captureWavSample({
    Duration duration = const Duration(seconds: 4),
    int sampleRate = 16000,
  }) async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) return null;

      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}${Platform.pathSeparator}'
          'voice_${DateTime.now().millisecondsSinceEpoch}.wav';

      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.wav,
          numChannels: 1,
          sampleRate: sampleRate,
          bitRate: 128000,
        ),
        path: path,
      );

      await Future<void>.delayed(duration);
      final recordedPath = await _recorder.stop();
      return recordedPath;
    } catch (_) {
      try {
        await _recorder.stop();
      } catch (_) {}
      return null;
    }
  }

  static Future<void> stopIfRecording() async {
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {}
  }
}
