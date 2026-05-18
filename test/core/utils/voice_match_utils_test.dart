import 'package:flutter_test/flutter_test.dart';
import 'package:sccp_mobile/core/utils/voice_match_utils.dart';

void main() {
  group('VoiceMatchUtils.normalize', () {
    test('normalizes accents and symbols', () {
      final normalized = VoiceMatchUtils.normalize('código, patrón Ñ-1');
      expect(normalized, 'CODIGO PATRON N 1');
    });

    test('collapses repeated spaces', () {
      final normalized = VoiceMatchUtils.normalize('  ALFA   BRAVO  ');
      expect(normalized, 'ALFA BRAVO');
    });
  });

  group('VoiceMatchUtils.similarity', () {
    test('returns one for equivalent text with accents', () {
      final score = VoiceMatchUtils.similarity(
        'código alfa bravo',
        'CODIGO ALFA BRAVO',
      );
      expect(score, 1);
    });

    test('returns high score for a minor typo', () {
      final score = VoiceMatchUtils.similarity(
        'CODIGO ALFA BRAVO',
        'CODIGO ALFA BRVAVO',
      );
      expect(score, greaterThan(0.9));
    });

    test('returns low score for different phrase', () {
      final score = VoiceMatchUtils.similarity(
        'DELTA SIERRA TANGO',
        'CODIGO ALFA BRAVO',
      );
      expect(score, lessThan(0.45));
    });

    test('keeps high score when recognized text has trailing noise', () {
      final score = VoiceMatchUtils.similarity(
        'OFICIAL ACTIVO OBLIGATORIO CLAVE ALFA 0900 PARTE CONTINGENCIA REPORTE PARTE',
        'OFICIAL ACTIVO OBLIGATORIO CLAVE ALFA 0900',
      );
      expect(score, greaterThan(0.75));
    });
  });

  group('VoiceMatchUtils.hasCoreChallengeMatch', () {
    test('accepts phrase when key tokens and numeric code are present', () {
      final ok = VoiceMatchUtils.hasCoreChallengeMatch(
        'OBLIGATORIO CLAVE ALFA 0900 OFICIAL ACTIVO',
        'OFICIAL ACTIVO OBLIGATORIO CLAVE ALFA 0900',
      );
      expect(ok, isTrue);
    });

    test('rejects phrase when numeric code is missing', () {
      final ok = VoiceMatchUtils.hasCoreChallengeMatch(
        'OFICIAL ACTIVO OBLIGATORIO CLAVE ALFA',
        'OFICIAL ACTIVO OBLIGATORIO CLAVE ALFA 0900',
      );
      expect(ok, isFalse);
    });
  });
}
