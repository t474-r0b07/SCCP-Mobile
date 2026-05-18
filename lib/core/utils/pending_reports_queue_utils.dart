import 'dart:convert';

class PendingReportsQueueUtils {
  static const Duration _maxAge = Duration(hours: 36);
  static const Duration _futureTolerance = Duration(minutes: 10);

  static List<Map<String, dynamic>> decode(String? raw) {
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];

      final queue = <Map<String, dynamic>>[];
      for (final item in decoded) {
        final asMap = _toStringDynamicMap(item);
        if (asMap == null) continue;
        if (!_isLikelyOperationalReport(asMap)) continue;
        if (!_hasReasonableTimestamp(asMap)) continue;
        queue.add(asMap);
      }
      return queue;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static List<Map<String, dynamic>> enqueue({
    required List<Map<String, dynamic>> queue,
    required Map<String, dynamic> report,
    required int maxItems,
  }) {
    final next = <Map<String, dynamic>>[];
    final newItem = Map<String, dynamic>.from(report);
    final newId = newItem['id_reporte']?.toString().trim();

    bool replaced = false;
    for (final item in queue) {
      final current = Map<String, dynamic>.from(item);
      final currentId = current['id_reporte']?.toString().trim();
      if (!replaced &&
          newId != null &&
          newId.isNotEmpty &&
          currentId == newId) {
        next.add(newItem);
        replaced = true;
      } else {
        next.add(current);
      }
    }
    if (!replaced) {
      next.add(newItem);
    }
    return trim(next, maxItems);
  }

  static List<Map<String, dynamic>> trim(
    List<Map<String, dynamic>> queue,
    int maxItems,
  ) {
    if (maxItems <= 0) return <Map<String, dynamic>>[];
    if (queue.length <= maxItems) return List<Map<String, dynamic>>.from(queue);
    final overflow = queue.length - maxItems;
    return List<Map<String, dynamic>>.from(queue.skip(overflow));
  }

  static String encode(List<Map<String, dynamic>> queue) {
    return jsonEncode(queue);
  }

  static Map<String, dynamic>? _toStringDynamicMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    if (value is Map) {
      try {
        return value.cast<String, dynamic>();
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static bool _isLikelyOperationalReport(Map<String, dynamic> item) {
    final idReporte = item['id_reporte']?.toString().trim() ?? '';
    final idOficial = item['id_oficial_ref']?.toString().trim() ?? '';
    return idReporte.isNotEmpty && idOficial.isNotEmpty;
  }

  static bool _hasReasonableTimestamp(Map<String, dynamic> item) {
    final raw = item['fecha_hora']?.toString().trim();
    if (raw == null || raw.isEmpty) return true;

    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return false;

    final nowUtc = DateTime.now().toUtc();
    final tsUtc = parsed.toUtc();
    if (tsUtc.isAfter(nowUtc.add(_futureTolerance))) return false;
    if (tsUtc.isBefore(nowUtc.subtract(_maxAge))) return false;
    return true;
  }
}
