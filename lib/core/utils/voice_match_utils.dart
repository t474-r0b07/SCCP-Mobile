import 'dart:math' as math;

class VoiceMatchUtils {
  static String normalize(String value) {
    var normalized = value.toUpperCase();

    const replacements = <String, String>{
      'Á': 'A',
      'À': 'A',
      'Ä': 'A',
      'Â': 'A',
      'Ã': 'A',
      'É': 'E',
      'È': 'E',
      'Ë': 'E',
      'Ê': 'E',
      'Í': 'I',
      'Ì': 'I',
      'Ï': 'I',
      'Î': 'I',
      'Ó': 'O',
      'Ò': 'O',
      'Ö': 'O',
      'Ô': 'O',
      'Õ': 'O',
      'Ú': 'U',
      'Ù': 'U',
      'Ü': 'U',
      'Û': 'U',
      'Ñ': 'N',
      'Ç': 'C',
    };

    replacements.forEach((source, target) {
      normalized = normalized.replaceAll(source, target);
    });

    return normalized
        .replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static double similarity(String recognized, String expected) {
    final a = normalize(recognized);
    final b = normalize(expected);
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;

    // If one phrase fully contains the other, prefer a high score.
    if (a.contains(b) || b.contains(a)) {
      final shorter = math.min(a.length, b.length);
      final longer = math.max(a.length, b.length);
      final ratio = longer == 0 ? 0.0 : shorter / longer;
      return (0.90 + (ratio * 0.10)).clamp(0.0, 1.0);
    }

    final charScore = _charSimilarity(a, b);
    final tokenScore = _tokenSimilarity(a, b);
    return math.max(charScore, tokenScore);
  }

  static bool hasCoreChallengeMatch(String recognized, String expected) {
    final rec = normalize(recognized);
    final exp = normalize(expected);
    if (rec.isEmpty || exp.isEmpty) return false;

    final recTokens = rec.split(' ').where((t) => t.isNotEmpty).toList();
    final expTokens = exp.split(' ').where((t) => t.isNotEmpty).toList();
    if (recTokens.isEmpty || expTokens.isEmpty) return false;

    final hasClaveInExpected = expTokens.contains('CLAVE');
    if (hasClaveInExpected) {
      final claveMatched =
          recTokens.any((t) => _tokenPairSimilarity(t, 'CLAVE') >= 0.80);
      if (!claveMatched) return false;
    }

    final codeToken = expTokens.firstWhere(
      (t) => RegExp(r'\d').hasMatch(t),
      orElse: () => '',
    );
    if (codeToken.isNotEmpty) {
      final codeMatched =
          recTokens.any((t) => _tokenPairSimilarity(t, codeToken) >= 0.80);
      if (!codeMatched) return false;
    }

    final contentTokens = expTokens
        .where((t) => t != 'CLAVE' && !RegExp(r'^\d+$').hasMatch(t))
        .toList();
    if (contentTokens.isEmpty) return true;

    var matched = 0;
    for (final token in contentTokens) {
      final ok = recTokens.any((r) => _tokenPairSimilarity(r, token) >= 0.76);
      if (ok) matched++;
    }

    final requiredMatches = math.min(
      contentTokens.length,
      contentTokens.length <= 4 ? 2 : 3,
    );
    return matched >= requiredMatches;
  }

  static double _charSimilarity(String a, String b) {
    final distance = levenshteinDistance(a, b);
    final maxLen = a.length > b.length ? a.length : b.length;
    if (maxLen == 0) return 0;
    return (1 - (distance / maxLen)).clamp(0.0, 1.0);
  }

  static double _tokenSimilarity(String recognized, String expected) {
    final recTokens = recognized.split(' ').where((t) => t.isNotEmpty).toList();
    final expTokens = expected.split(' ').where((t) => t.isNotEmpty).toList();
    if (recTokens.isEmpty || expTokens.isEmpty) return 0;

    final usedRecIndexes = <int>{};
    var matched = 0;
    var totalMatchedScore = 0.0;

    for (final exp in expTokens) {
      var bestScore = 0.0;
      var bestIdx = -1;
      for (var i = 0; i < recTokens.length; i++) {
        if (usedRecIndexes.contains(i)) continue;
        final score = _tokenPairSimilarity(exp, recTokens[i]);
        if (score > bestScore) {
          bestScore = score;
          bestIdx = i;
        }
      }
      if (bestIdx >= 0 && bestScore >= 0.72) {
        usedRecIndexes.add(bestIdx);
        matched++;
        totalMatchedScore += bestScore;
      }
    }

    if (matched == 0) return 0;
    final recall = matched / expTokens.length;
    final avgScore = totalMatchedScore / matched;
    var score = (recall * 0.72) + (avgScore * 0.28);
    if (recall >= 0.85 && avgScore >= 0.78) {
      score += 0.04;
    }
    return score.clamp(0.0, 1.0);
  }

  static double _tokenPairSimilarity(String a, String b) {
    if (a == b) return 1;
    if (a.isEmpty || b.isEmpty) return 0;

    if (a.length >= 4 && b.length >= 4) {
      if (a.startsWith(b) || b.startsWith(a)) {
        return 0.86;
      }
    }

    return _charSimilarity(a, b);
  }

  static int levenshteinDistance(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final rows = a.length + 1;
    final cols = b.length + 1;
    final dp = List.generate(rows, (_) => List<int>.filled(cols, 0));

    for (int i = 0; i < rows; i++) {
      dp[i][0] = i;
    }
    for (int j = 0; j < cols; j++) {
      dp[0][j] = j;
    }

    for (int i = 1; i < rows; i++) {
      for (int j = 1; j < cols; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        dp[i][j] = [
          dp[i - 1][j] + 1,
          dp[i][j - 1] + 1,
          dp[i - 1][j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
    }

    return dp[a.length][b.length];
  }
}
