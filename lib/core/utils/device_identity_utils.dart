import 'dart:math';
import 'package:android_id/android_id.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdentityUtils {
  static const _deviceIdKey = 'device_identifier';
  static const AndroidId _androidId = AndroidId();

  static Future<String> getOrCreateDeviceIdentifier() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final id = await _androidId.getId();
        if (id != null && id.trim().isNotEmpty) {
          final stable = 'ANDROID_${id.trim().toUpperCase()}';
          await prefs.setString(_deviceIdKey, stable);
          return stable;
        }
      } catch (_) {
        // Fallback abajo.
      }
    }

    final random = Random.secure();
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final entropy = random.nextInt(0x7fffffff).toRadixString(36);
    final platformLabel =
        kIsWeb ? 'WEB' : defaultTargetPlatform.name.toUpperCase();
    final generated = '${platformLabel}_$now$entropy'.toUpperCase();

    await prefs.setString(_deviceIdKey, generated);
    return generated;
  }
}
