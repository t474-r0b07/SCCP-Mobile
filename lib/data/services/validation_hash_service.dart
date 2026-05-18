import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:battery_plus/battery_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ValidationHashResult {
  final bool ok;
  final String hash;
  final Map<String, dynamic> envelope;
  final bool mockSuspected;
  final String message;

  const ValidationHashResult({
    required this.ok,
    required this.hash,
    required this.envelope,
    required this.mockSuspected,
    required this.message,
  });
}

class ValidationHashService {
  ValidationHashService._();

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(),
  );
  static const String _deviceSecretKey = 'secure_evidence_hmac_secret_v2';
  static const String _sequenceKey = 'evidence_sequence_v2';
  static const String _lastHashKey = 'evidence_last_hash_v2';
  static const String _recentHashesKey = 'evidence_recent_hashes_v2';
  static const String _envelopeArchiveKey = 'evidence_envelope_archive_v2';
  static const int _maxRecentHashes = 64;
  static const int _maxArchiveEntries = 40;
  static const int _maxCaptureAgeSeconds = 180;

  static Future<ValidationHashResult> buildEvidenceHash({
    required String oficialId,
    required String imagePath,
    String? slotLabel,
    String? expectedPhrase,
    String? recognizedText,
    String? idSorpresa,
    bool isParteSorpresa = false,
  }) async {
    final now = DateTime.now().toUtc();
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId =
          prefs.getString('user_device_id') ?? prefs.getString('user_imei');

      final imageInfo = await _readImageStub(imagePath);
      if (imageInfo['exists'] != true) {
        return const ValidationHashResult(
          ok: false,
          hash: '',
          envelope: <String, dynamic>{},
          mockSuspected: false,
          message: 'EVIDENCIA_IMAGEN_NO_ENCONTRADA',
        );
      }
      final ageSeconds = (imageInfo['age_seconds'] as int?) ?? -1;
      if (ageSeconds < 0 || ageSeconds > _maxCaptureAgeSeconds) {
        return ValidationHashResult(
          ok: false,
          hash: '',
          envelope: const <String, dynamic>{},
          mockSuspected: false,
          message:
              'EVIDENCIA_CAPTURA_NO_RECIENTE (${ageSeconds < 0 ? "N/D" : "${ageSeconds}s"})',
        );
      }

      final imageSha256 = (imageInfo['sha256'] ?? '').toString();
      if (imageSha256.isEmpty) {
        return const ValidationHashResult(
          ok: false,
          hash: '',
          envelope: <String, dynamic>{},
          mockSuspected: false,
          message: 'EVIDENCIA_HASH_IMAGEN_INVALIDO',
        );
      }
      final recentHashes = _readRecentHashes(prefs);
      if (recentHashes.contains(imageSha256)) {
        return const ValidationHashResult(
          ok: false,
          hash: '',
          envelope: <String, dynamic>{},
          mockSuspected: false,
          message: 'EVIDENCIA_REPLAY_DETECTADO',
        );
      }

      final battery = await _readBatteryLevel();
      final gpsPayload = await _readGpsPayload();
      final wifiPayload = await _readWifiPayload();
      final bluetoothPayload = await _scanBluetoothNearby();
      final mockSuspected = gpsPayload['is_mocked'] == true;
      if (mockSuspected) {
        return const ValidationHashResult(
          ok: false,
          hash: '',
          envelope: <String, dynamic>{},
          mockSuspected: true,
          message: 'EVIDENCIA_GPS_MOCK_DETECTADO',
        );
      }

      final gpsAccuracy = (gpsPayload['accuracy'] as num?)?.toDouble();
      final gpsReliable = gpsAccuracy != null && gpsAccuracy.isFinite
          ? gpsAccuracy <= 120
          : false;
      if (!gpsReliable) {
        return ValidationHashResult(
          ok: false,
          hash: '',
          envelope: const <String, dynamic>{},
          mockSuspected: false,
          message:
              'EVIDENCIA_GPS_NO_CONFIABLE (accuracy:${gpsAccuracy?.toStringAsFixed(1) ?? "N/D"})',
        );
      }

      final sequence = await _nextSequence(prefs);
      final previousHash = prefs.getString(_lastHashKey) ?? '';
      final phraseDigest = _shortDigest(expectedPhrase ?? '');
      final recognizedDigest = _shortDigest(recognizedText ?? '');
      final sessionKind = isParteSorpresa ? 'PARTE_SORPRESA' : 'PARTE_OFICIAL';

      final envelope = <String, dynamic>{
        'v': 2,
        'official_id': oficialId.trim(),
        'device_id': (deviceId ?? '').trim(),
        'timestamp_utc': now.toIso8601String(),
        'image_stub': imageInfo,
        'image_sha256': imageSha256,
        'gps': gpsPayload,
        'wifi': wifiPayload,
        'bluetooth': bluetoothPayload,
        'context': {
          'slot_label': (slotLabel ?? '').trim(),
          'session_kind': sessionKind,
          'id_sorpresa': (idSorpresa ?? '').trim(),
          'challenge_digest': phraseDigest,
          'recognized_digest': recognizedDigest,
        },
        'proof': {
          'sequence': sequence,
          'previous_hash': previousHash,
        },
        'system': {
          'battery_pct': battery,
          'mock_suspected': mockSuspected,
          'platform': Platform.operatingSystem,
        },
      };

      final deviceSecret = await _getOrCreateDeviceSecret();
      final canonical = _canonicalJson(envelope);
      final hmacSig = _hmacSha256(deviceSecret, canonical);
      final digest =
          sha256.convert(utf8.encode('$canonical|sig:$hmacSig')).toString();
      envelope['proof_signature'] = hmacSig;
      envelope['proof_token'] = _proofToken(
        sequence: sequence,
        digest: digest,
        signature: hmacSig,
      );
      envelope['hash'] = digest;

      _pushRecentHash(prefs, imageSha256);
      await prefs.setString(_lastHashKey, digest);
      await _appendEnvelopeArchive(prefs, envelope);

      return ValidationHashResult(
        ok: true,
        hash: digest,
        envelope: envelope,
        mockSuspected: mockSuspected,
        message: 'HASH_VALIDATION_OK',
      );
    } catch (_) {
      return const ValidationHashResult(
        ok: false,
        hash: '',
        envelope: <String, dynamic>{},
        mockSuspected: false,
        message: 'HASH_VALIDATION_FAILED',
      );
    }
  }

  static Future<String> _getOrCreateDeviceSecret() async {
    try {
      final existing = await _secureStorage.read(key: _deviceSecretKey);
      if (existing != null && existing.trim().isNotEmpty) {
        return existing.trim();
      }
      final random = math.Random.secure();
      final bytes = List<int>.generate(32, (_) => random.nextInt(256));
      final generated = base64Url.encode(bytes);
      await _secureStorage.write(key: _deviceSecretKey, value: generated);
      return generated;
    } catch (_) {
      final fallback = sha256
          .convert(utf8.encode('fallback-evidence-secret-v2:${DateTime.now()}'))
          .toString();
      return fallback;
    }
  }

  static String _hmacSha256(String secret, String payload) {
    final key = utf8.encode(secret);
    final message = utf8.encode(payload);
    return Hmac(sha256, key).convert(message).toString();
  }

  static String _proofToken({
    required int sequence,
    required String digest,
    required String signature,
  }) {
    final d = digest.length > 16 ? digest.substring(0, 16) : digest;
    final s = signature.length > 12 ? signature.substring(0, 12) : signature;
    return 'EV2:$sequence:$d:$s';
  }

  static String _shortDigest(String raw) {
    final text = raw.trim().toUpperCase();
    if (text.isEmpty) return '';
    return sha256.convert(utf8.encode(text)).toString().substring(0, 16);
  }

  static List<String> _readRecentHashes(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_recentHashesKey);
      if (raw == null || raw.trim().isEmpty) return <String>[];
      final data = jsonDecode(raw);
      if (data is! List) return <String>[];
      return data.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    } catch (_) {
      return <String>[];
    }
  }

  static Future<void> _pushRecentHash(
    SharedPreferences prefs,
    String imageSha256,
  ) async {
    final items = _readRecentHashes(prefs);
    items.add(imageSha256);
    while (items.length > _maxRecentHashes) {
      items.removeAt(0);
    }
    await prefs.setString(_recentHashesKey, jsonEncode(items));
  }

  static Future<int> _nextSequence(SharedPreferences prefs) async {
    final current = prefs.getInt(_sequenceKey) ?? 0;
    final next = current + 1;
    await prefs.setInt(_sequenceKey, next);
    return next;
  }

  static Future<void> _appendEnvelopeArchive(
    SharedPreferences prefs,
    Map<String, dynamic> envelope,
  ) async {
    try {
      final raw = prefs.getString(_envelopeArchiveKey);
      final list = <Map<String, dynamic>>[];
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              list.add(item.cast<String, dynamic>());
            }
          }
        }
      }
      list.add(envelope);
      while (list.length > _maxArchiveEntries) {
        list.removeAt(0);
      }
      await prefs.setString(_envelopeArchiveKey, jsonEncode(list));
    } catch (_) {
      // Best effort local audit archive.
    }
  }

  static Future<int?> _readBatteryLevel() async {
    try {
      return await Battery().batteryLevel;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> _readGpsPayload() async {
    final payload = <String, dynamic>{
      'source': 'none',
      'lat': null,
      'lng': null,
      'accuracy': null,
      'is_mocked': false,
      'location_enabled': false,
      'permission': 'unknown',
    };

    try {
      payload['location_enabled'] = await Geolocator.isLocationServiceEnabled();
      final permission = await Geolocator.checkPermission();
      payload['permission'] = permission.name;

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 6),
        );
        payload['source'] = 'current';
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
        if (pos != null) payload['source'] = 'last_known';
      }

      if (pos != null) {
        payload['lat'] = pos.latitude;
        payload['lng'] = pos.longitude;
        payload['accuracy'] = pos.accuracy;
        payload['is_mocked'] = pos.isMocked;
      }
    } catch (_) {}

    return payload;
  }

  static Future<Map<String, dynamic>> _readWifiPayload() async {
    final payload = <String, dynamic>{
      'ssid': '',
      'bssid': '',
      'ok': false,
      'permission': 'missing',
    };
    try {
      final permission = await Permission.locationWhenInUse.status;
      if (!permission.isGranted) {
        payload['permission'] = permission.name;
        return payload;
      }

      final info = NetworkInfo();
      final ssid = await info.getWifiName();
      final bssid = await info.getWifiBSSID();
      payload['ssid'] = (ssid ?? '').replaceAll('"', '');
      payload['bssid'] = (bssid ?? '').trim();
      payload['ok'] = payload['bssid'].toString().isNotEmpty;
      payload['permission'] = 'granted';
      return payload;
    } catch (_) {
      return payload;
    }
  }

  static Future<Map<String, dynamic>> _scanBluetoothNearby() async {
    final payload = <String, dynamic>{
      'ok': false,
      'count': 0,
      'beacons': <String>[],
      'permission': 'missing',
    };
    try {
      final supported = await FlutterBluePlus.isSupported;
      if (!supported) return payload;

      final scanPermission = await Permission.bluetoothScan.status;
      if (!scanPermission.isGranted) {
        payload['permission'] = scanPermission.name;
        return payload;
      }
      final connectPermission = await Permission.bluetoothConnect.status;
      if (!connectPermission.isGranted) {
        payload['permission'] = connectPermission.name;
        return payload;
      }
      payload['permission'] = 'granted';

      final discovered = <String>{};
      final sub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final id = r.device.remoteId.str.trim();
          if (id.isEmpty) continue;
          final entry = '$id@${r.rssi}';
          discovered.add(entry);
          if (discovered.length >= 20) break;
        }
      });
      try {
        await FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 3),
        );
        await Future<void>.delayed(const Duration(seconds: 3));
      } catch (_) {
        // Keep whatever we captured.
      } finally {
        try {
          await FlutterBluePlus.stopScan();
        } catch (_) {}
        await sub.cancel();
      }

      final list = discovered.toList()..sort();
      payload['ok'] = true;
      payload['count'] = list.length;
      payload['beacons'] = list;
      return payload;
    } catch (_) {
      return payload;
    }
  }

  static Future<Map<String, dynamic>> _readImageStub(String path) async {
    final out = <String, dynamic>{
      'exists': false,
      'name': '',
      'size_bytes': 0,
      'modified_utc': '',
      'age_seconds': -1,
      'mime_hint': '',
      'contains_exif': false,
      'sha256': '',
    };
    try {
      final file = File(path);
      if (!await file.exists()) return out;
      out['exists'] = true;
      final stat = await file.stat();
      out['name'] = file.uri.pathSegments.isEmpty
          ? 'evidence.jpg'
          : file.uri.pathSegments.last;
      out['size_bytes'] = stat.size;
      final modifiedUtc = stat.modified.toUtc();
      out['modified_utc'] = modifiedUtc.toIso8601String();
      out['age_seconds'] =
          DateTime.now().toUtc().difference(modifiedUtc).inSeconds;
      if (stat.size < 5 * 1024 || stat.size > 10 * 1024 * 1024) {
        out['mime_hint'] = 'size_out_of_range';
        return out;
      }

      final bytes = await file.readAsBytes();
      out['sha256'] = sha256.convert(bytes).toString();
      out['mime_hint'] = _mimeHint(bytes);
      out['contains_exif'] = _containsExif(bytes);
      return out;
    } catch (_) {
      return out;
    }
  }

  static String _mimeHint(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'image/png';
    }
    return 'unknown';
  }

  static bool _containsExif(List<int> bytes) {
    if (bytes.isEmpty) return false;
    final source = ascii
        .decode(bytes.take(math.min(bytes.length, 64 * 1024)).toList(),
            allowInvalid: true)
        .toUpperCase();
    return source.contains('EXIF');
  }

  static String _canonicalJson(dynamic value) {
    if (value is Map) {
      final sortedKeys = value.keys.map((e) => e.toString()).toList()..sort();
      final out = <String, dynamic>{};
      for (final key in sortedKeys) {
        out[key] = _canonicalize(value[key]);
      }
      return jsonEncode(out);
    }
    return jsonEncode(_canonicalize(value));
  }

  static dynamic _canonicalize(dynamic value) {
    if (value is Map) {
      final sortedKeys = value.keys.map((e) => e.toString()).toList()..sort();
      final out = <String, dynamic>{};
      for (final key in sortedKeys) {
        out[key] = _canonicalize(value[key]);
      }
      return out;
    }
    if (value is List) {
      return value.map(_canonicalize).toList();
    }
    return value;
  }
}
