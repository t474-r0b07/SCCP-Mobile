import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecurityStorageService {
  static const _voiceProfileCodeKey = 'secure_voice_profile_code';
  static const _voiceBiometricProfileKey = 'secure_voice_biometric_profile';

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(),
  );

  static Future<void> writeVoiceProfileCode(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) return;

    try {
      await _secureStorage.write(key: _voiceProfileCodeKey, value: normalized);
    } catch (e) {
      debugPrint('SecurityStorage write failed: $e');
    }
  }

  static Future<String?> readVoiceProfileCode() async {
    try {
      final fromSecure = await _secureStorage.read(key: _voiceProfileCodeKey);
      if (fromSecure != null && fromSecure.trim().isNotEmpty) {
        return fromSecure.trim();
      }
    } catch (e) {
      debugPrint('SecurityStorage read failed: $e');
    }

    // Fallback temporal para compatibilidad con instalaciones anteriores.
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString('voice_profile_code');
      if (legacy != null && legacy.trim().isNotEmpty) {
        await writeVoiceProfileCode(legacy);
        return legacy.trim();
      }
    } catch (_) {
      // Silencioso
    }
    return null;
  }

  static Future<void> clearVoiceProfileCode() async {
    try {
      await _secureStorage.delete(key: _voiceProfileCodeKey);
    } catch (e) {
      debugPrint('SecurityStorage clear failed: $e');
    }
  }

  static Future<void> writeVoiceBiometricProfile(List<double> embedding) async {
    if (embedding.isEmpty) return;
    try {
      await _secureStorage.write(
        key: _voiceBiometricProfileKey,
        value: jsonEncode(embedding),
      );
    } catch (e) {
      debugPrint('SecurityStorage write biometric failed: $e');
    }
  }

  static Future<List<double>?> readVoiceBiometricProfile() async {
    try {
      final raw = await _secureStorage.read(key: _voiceBiometricProfileKey);
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      final out = decoded
          .map((e) => (e as num?)?.toDouble())
          .whereType<double>()
          .toList();
      return out.isEmpty ? null : out;
    } catch (e) {
      debugPrint('SecurityStorage read biometric failed: $e');
      return null;
    }
  }

  static Future<void> clearVoiceBiometricProfile() async {
    try {
      await _secureStorage.delete(key: _voiceBiometricProfileKey);
    } catch (e) {
      debugPrint('SecurityStorage clear biometric failed: $e');
    }
  }
}
