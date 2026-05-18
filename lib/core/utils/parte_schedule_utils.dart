import 'shift_utils.dart';

class ParteScheduleUtils {
  static const int firstSlotHour = 9;
  static const List<String> slotTimes = [
    '09:00',
    '12:00',
    '15:00',
    '18:00',
    '21:00'
  ];
  static const int graceMinutes = 10;

  static DateTime operationalDayAnchor(DateTime now) {
    final local = now.toLocal();
    if (local.hour < firstSlotHour) {
      final prev = local.subtract(const Duration(days: 1));
      return DateTime(prev.year, prev.month, prev.day);
    }
    return DateTime(local.year, local.month, local.day);
  }

  static List<DateTime> slotsForNow(DateTime now) {
    final day = operationalDayAnchor(now);
    return slotTimes.map((value) {
      final parts = value.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      return DateTime(day.year, day.month, day.day, hour, minute);
    }).toList();
  }

  static DateTime? activeSlot(DateTime now, {int grace = graceMinutes}) {
    final local = now.toLocal();
    for (final slot in slotsForNow(local)) {
      final end = slot.add(Duration(minutes: grace));
      final inWindow = !local.isBefore(slot) && local.isBefore(end);
      if (inWindow) return slot;
    }
    return null;
  }

  static DateTime? nextSlot(DateTime now) {
    final local = now.toLocal();
    for (final slot in slotsForNow(local)) {
      if (slot.isAfter(local)) return slot;
    }
    final nextDay = local.add(const Duration(days: 1));
    final nextSlots = slotsForNow(nextDay);
    return nextSlots.isEmpty ? null : nextSlots.first;
  }

  static String slotKey(DateTime slot) {
    return '${slot.year.toString().padLeft(4, '0')}${slot.month.toString().padLeft(2, '0')}${slot.day.toString().padLeft(2, '0')}_${slot.hour.toString().padLeft(2, '0')}${slot.minute.toString().padLeft(2, '0')}';
  }

  static bool isOperationalShiftNow(
      {String? turno, String? grupo, DateTime? now}) {
    return ShiftUtils.isWithinShift(turno, grupo: grupo, now: now);
  }
}
