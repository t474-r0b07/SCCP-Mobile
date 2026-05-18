import 'package:flutter_test/flutter_test.dart';
import 'package:sccp_mobile/core/utils/voice_challenge_utils.dart';

void main() {
  test('genera frase no vacia para parte obligatorio', () {
    final phrase = VoiceChallengeUtils.generateChallengePhrase(
      isParteSorpresa: false,
      slot: DateTime(2026, 2, 23, 12, 0),
      seed: 11,
    );

    expect(phrase.trim().isNotEmpty, true);
    expect(phrase.contains('OBLIGATORIO'), true);
    expect(phrase.contains('1200'), true);
  });

  test('genera frase no vacia para parte sorpresa', () {
    final phrase = VoiceChallengeUtils.generateChallengePhrase(
      isParteSorpresa: true,
      slot: DateTime(2026, 2, 23, 12, 0),
      idSorpresa: 'PS_123',
      seed: 19,
    );

    expect(phrase.trim().isNotEmpty, true);
    expect(phrase.contains('SORPRESA'), true);
    expect(phrase.contains('1200'), true);
  });
}
