import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AndroidSystemService {
  static const MethodChannel _channel = MethodChannel('sccp/mobile_system');

  static bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!_isAndroid) return true;
    try {
      final value =
          await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return value ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!_isAndroid) return true;
    try {
      final value =
          await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
      return value ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openIgnoreBatteryOptimizationSettings() async {
    if (!_isAndroid) return false;
    try {
      final value = await _channel.invokeMethod<bool>(
        'openIgnoreBatteryOptimizationSettings',
      );
      return value ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openDataUsageSettings() async {
    if (!_isAndroid) return false;
    try {
      final value = await _channel.invokeMethod<bool>('openDataUsageSettings');
      return value ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Android ConnectivityManager:
  /// 1 = enabled, 2 = whitelisted, 3 = disabled.
  static Future<int> getRestrictBackgroundStatus() async {
    if (!_isAndroid) return 0;
    try {
      final value = await _channel.invokeMethod<int>('getRestrictBackgroundStatus');
      return value ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<bool> isBackgroundDataRestricted() async {
    if (!_isAndroid) return false;
    final status = await getRestrictBackgroundStatus();
    return status == 1;
  }
}
