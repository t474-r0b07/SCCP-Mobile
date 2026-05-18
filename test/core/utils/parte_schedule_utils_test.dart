import 'package:flutter_test/flutter_test.dart';
import 'package:sccp_mobile/core/utils/parte_schedule_utils.dart';

void main() {
  group('ParteScheduleUtils', () {
    test('operationalDayAnchor uses previous day before 09:00', () {
      final anchor = ParteScheduleUtils.operationalDayAnchor(
        DateTime(2026, 2, 18, 8, 30),
      );

      expect(anchor, DateTime(2026, 2, 17));
    });

    test('activeSlot returns current slot inside grace window', () {
      final slot = ParteScheduleUtils.activeSlot(
        DateTime(2026, 2, 18, 9, 5),
      );

      expect(slot, DateTime(2026, 2, 18, 9, 0));
    });

    test('activeSlot closes at grace boundary', () {
      final slot = ParteScheduleUtils.activeSlot(
        DateTime(2026, 2, 18, 9, 10),
      );

      expect(slot, isNull);
    });

    test('nextSlot returns next same-day slot', () {
      final next = ParteScheduleUtils.nextSlot(
        DateTime(2026, 2, 18, 9, 0),
      );

      expect(next, DateTime(2026, 2, 18, 12, 0));
    });

    test('nextSlot early morning resolves to same day 09:00', () {
      final next = ParteScheduleUtils.nextSlot(
        DateTime(2026, 2, 18, 8, 30),
      );

      expect(next, DateTime(2026, 2, 18, 9, 0));
    });

    test('nextSlot after last slot resolves to next day 09:00', () {
      final next = ParteScheduleUtils.nextSlot(
        DateTime(2026, 2, 18, 22, 0),
      );

      expect(next, DateTime(2026, 2, 19, 9, 0));
    });

    test('slotKey returns stable key format', () {
      final key = ParteScheduleUtils.slotKey(
        DateTime(2026, 2, 18, 9, 0),
      );

      expect(key, '20260218_0900');
    });
  });
}
