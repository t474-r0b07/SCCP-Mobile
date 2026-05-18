import 'package:flutter_test/flutter_test.dart';
import 'package:sccp_mobile/core/utils/shift_utils.dart';

void main() {
  group('ShiftUtils.activeGroup', () {
    test('uses cycle start date as ALFA day 1', () {
      final group = ShiftUtils.activeGroup(
        now: DateTime(2026, 2, 28, 9, 0),
      );

      expect(group, 'ALFA');
    });

    test('switches to BRAVO on day 2', () {
      final group = ShiftUtils.activeGroup(
        now: DateTime(2026, 3, 1, 9, 0),
      );

      expect(group, 'BRAVO');
    });

    test('before 08:00 still uses previous operational day', () {
      final group = ShiftUtils.activeGroup(
        now: DateTime(2026, 3, 1, 7, 59),
      );

      expect(group, 'ALFA');
    });

    test('keeps ALFA on 2026-02-27/2026-02-28 and BRAVO on 2026-03-01/2026-03-02', () {
      expect(
        ShiftUtils.activeGroup(now: DateTime(2026, 2, 27, 10, 0)),
        'ALFA',
      );
      expect(
        ShiftUtils.activeGroup(now: DateTime(2026, 2, 28, 10, 0)),
        'ALFA',
      );
      expect(
        ShiftUtils.activeGroup(now: DateTime(2026, 3, 1, 10, 0)),
        'BRAVO',
      );
      expect(
        ShiftUtils.activeGroup(now: DateTime(2026, 3, 2, 10, 0)),
        'BRAVO',
      );
    });
  });

  group('ShiftUtils.isWithinShift', () {
    test('validates group access against cycle', () {
      final now = DateTime(2026, 3, 1, 9, 0);
      expect(ShiftUtils.isWithinShift(null, grupo: 'BRAVO', now: now), isTrue);
      expect(ShiftUtils.isWithinShift(null, grupo: 'ALFA', now: now), isFalse);
    });

    test('requires both group and shift window when both are provided', () {
      final now = DateTime(2026, 2, 28, 13, 0); // Dia ALFA activo
      expect(
        ShiftUtils.isWithinShift(
          '08:00-12:00',
          grupo: 'ALFA',
          now: now,
        ),
        isFalse,
      );
      expect(
        ShiftUtils.isWithinShift(
          '08:00-12:00',
          grupo: 'ALFA',
          now: DateTime(2026, 2, 28, 10, 0),
        ),
        isTrue,
      );
      expect(
        ShiftUtils.isWithinShift(
          '08:00-12:00',
          grupo: 'BRAVO',
          now: DateTime(2026, 2, 28, 10, 0),
        ),
        isFalse,
      );
    });

    test('supports crossing-midnight windows', () {
      expect(
        ShiftUtils.isWithinShift(
          '22:00-06:00',
          now: DateTime(2026, 2, 18, 23, 0),
        ),
        isTrue,
      );
      expect(
        ShiftUtils.isWithinShift(
          '22:00-06:00',
          now: DateTime(2026, 2, 19, 5, 59),
        ),
        isTrue,
      );
      expect(
        ShiftUtils.isWithinShift(
          '22:00-06:00',
          now: DateTime(2026, 2, 19, 6, 0),
        ),
        isFalse,
      );
    });
  });

  group('ShiftUtils.timeUntilShiftStart', () {
    test('returns zero if group is currently active', () {
      final result = ShiftUtils.timeUntilShiftStart(
        null,
        grupo: 'ALFA',
        now: DateTime(2026, 2, 28, 10, 0),
      );

      expect(result, Duration.zero);
    });

    test('returns remaining time to next active group day', () {
      final result = ShiftUtils.timeUntilShiftStart(
        null,
        grupo: 'BRAVO',
        now: DateTime(2026, 2, 28, 10, 0),
      );

      expect(result, const Duration(hours: 22));
    });

    test('returns remaining time for explicit shift window', () {
      final result = ShiftUtils.timeUntilShiftStart(
        '08:00-12:00',
        now: DateTime(2026, 2, 28, 7, 0),
      );
      expect(result, const Duration(hours: 1));
    });

    test('returns remaining time for combined group + shift window', () {
      final result = ShiftUtils.timeUntilShiftStart(
        '08:00-12:00',
        grupo: 'ALFA',
        now: DateTime(2026, 2, 28, 13, 0),
      );
      // Próxima ventana válida ALFA + horario:
      // martes 03/03/2026 08:00 (día 4 del ciclo).
      expect(result, const Duration(hours: 67));
    });
  });
}
