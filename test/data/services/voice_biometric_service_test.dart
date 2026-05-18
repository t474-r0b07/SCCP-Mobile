import 'package:flutter_test/flutter_test.dart';
import 'package:sccp_mobile/data/services/voice_biometric_service.dart';

void main() {
  group('VoiceBiometricService', () {
    test('cosineSimilarity returns 1 for identical vectors', () {
      final a = <double>[0.2, 0.4, -0.6, 0.1];
      final score = VoiceBiometricService.cosineSimilarity(a, a);
      expect(score, closeTo(1.0, 1e-9));
    });

    test('cosineSimilarity returns low score for orthogonal vectors', () {
      final a = <double>[1, 0, 0];
      final b = <double>[0, 1, 0];
      final score = VoiceBiometricService.cosineSimilarity(a, b);
      expect(score, closeTo(0.0, 1e-9));
    });

    test('averageEmbeddings normalizes result', () {
      final avg = VoiceBiometricService.averageEmbeddings([
        <double>[1, 0, 0],
        <double>[1, 0, 0],
        <double>[1, 0, 0],
      ]);
      expect(avg, isNotNull);
      expect(avg!.length, 3);
      expect(avg[0], closeTo(1.0, 1e-9));
      expect(avg[1], closeTo(0.0, 1e-9));
      expect(avg[2], closeTo(0.0, 1e-9));
    });

    test('verifyWavAgainstProfile fails fast with empty profile', () async {
      final result = await VoiceBiometricService.verifyWavAgainstProfile(
        wavPath: 'missing.wav',
        profileEmbedding: const <double>[],
      );
      expect(result.ok, isFalse);
      expect(result.message, contains('Perfil biometrico'));
    });
  });
}
