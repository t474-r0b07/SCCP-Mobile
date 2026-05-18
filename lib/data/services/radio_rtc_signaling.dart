import 'dart:convert';

class RadioRtcSignal {
  static const String prefix = '__RTC__';
  static const int version = 1;

  static const String offer = 'OFFER';
  static const String answer = 'ANSWER';
  static const String ice = 'ICE';
  static const String hangup = 'HANGUP';
  static const String reject = 'REJECT';

  final String action;
  final String callId;
  final String fromUser;
  final String toUser;
  final Map<String, dynamic> data;

  const RadioRtcSignal({
    required this.action,
    required this.callId,
    required this.fromUser,
    required this.toUser,
    this.data = const <String, dynamic>{},
  });

  String encode() {
    return '$prefix${jsonEncode(toJson())}';
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'v': version,
      'a': action.trim().toUpperCase(),
      'c': callId.trim(),
      'f': fromUser.trim(),
      't': toUser.trim(),
      'd': data,
    };
  }

  static bool isRtcPayload(String raw) {
    return raw.trimLeft().startsWith(prefix);
  }

  static RadioRtcSignal? tryParse(String raw) {
    final clean = raw.trimLeft();
    if (!clean.startsWith(prefix)) return null;
    final payload = clean.substring(prefix.length).trim();
    if (payload.isEmpty) return null;

    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return null;

      final action = (decoded['a'] ?? '').toString().trim().toUpperCase();
      final callId = (decoded['c'] ?? '').toString().trim();
      final fromUser = (decoded['f'] ?? '').toString().trim();
      final toUser = (decoded['t'] ?? '').toString().trim();
      final data = (decoded['d'] is Map)
          ? Map<String, dynamic>.from(decoded['d'])
          : <String, dynamic>{};

      if (action.isEmpty || callId.isEmpty) return null;
      return RadioRtcSignal(
        action: action,
        callId: callId,
        fromUser: fromUser,
        toUser: toUser,
        data: data,
      );
    } catch (_) {
      return null;
    }
  }
}
