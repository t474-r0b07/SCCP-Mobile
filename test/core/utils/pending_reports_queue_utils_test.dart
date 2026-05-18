import 'package:flutter_test/flutter_test.dart';
import 'package:sccp_mobile/core/utils/pending_reports_queue_utils.dart';

void main() {
  group('PendingReportsQueueUtils.decode', () {
    test('returns empty for null/empty/invalid json', () {
      expect(PendingReportsQueueUtils.decode(null), isEmpty);
      expect(PendingReportsQueueUtils.decode(''), isEmpty);
      expect(PendingReportsQueueUtils.decode('{oops'), isEmpty);
    });

    test('keeps only likely operational reports', () {
      const raw = '''
[
  {"id_reporte":"R1","id_oficial_ref":"OF1","foo":"bar"},
  {"id_reporte":"R2"},
  {"id_oficial_ref":"OF2"},
  {"other":"x"}
]
''';
      final result = PendingReportsQueueUtils.decode(raw);
      expect(result.length, 1);
      expect(result.first['id_reporte'], 'R1');
    });

    test('drops reports too far in the future', () {
      final future = DateTime.now().toUtc().add(const Duration(hours: 2));
      final raw = '''
[
  {"id_reporte":"R1","id_oficial_ref":"OF1","fecha_hora":"${future.toIso8601String()}"}
]
''';
      final result = PendingReportsQueueUtils.decode(raw);
      expect(result, isEmpty);
    });

    test('drops reports too old for retry queue', () {
      final old = DateTime.now().toUtc().subtract(const Duration(days: 3));
      final raw = '''
[
  {"id_reporte":"R1","id_oficial_ref":"OF1","fecha_hora":"${old.toIso8601String()}"}
]
''';
      final result = PendingReportsQueueUtils.decode(raw);
      expect(result, isEmpty);
    });
  });

  group('PendingReportsQueueUtils.enqueue/trim', () {
    test('enqueues and trims oldest when max reached', () {
      final queue = <Map<String, dynamic>>[
        {'id_reporte': 'R1', 'id_oficial_ref': 'OF'},
        {'id_reporte': 'R2', 'id_oficial_ref': 'OF'},
      ];

      final next = PendingReportsQueueUtils.enqueue(
        queue: queue,
        report: {'id_reporte': 'R3', 'id_oficial_ref': 'OF'},
        maxItems: 2,
      );

      expect(next.length, 2);
      expect(next.first['id_reporte'], 'R2');
      expect(next.last['id_reporte'], 'R3');
    });

    test('trim returns empty when maxItems <= 0', () {
      final trimmed = PendingReportsQueueUtils.trim(
        [
          {'id_reporte': 'R1', 'id_oficial_ref': 'OF'},
        ],
        0,
      );
      expect(trimmed, isEmpty);
    });
  });

  group('PendingReportsQueueUtils.encode', () {
    test('supports roundtrip with decode', () {
      final input = <Map<String, dynamic>>[
        {'id_reporte': 'R1', 'id_oficial_ref': 'OF1'},
        {'id_reporte': 'R2', 'id_oficial_ref': 'OF1'},
      ];

      final raw = PendingReportsQueueUtils.encode(input);
      final output = PendingReportsQueueUtils.decode(raw);
      expect(output.length, 2);
      expect(output[0]['id_reporte'], 'R1');
      expect(output[1]['id_reporte'], 'R2');
    });
  });
}
