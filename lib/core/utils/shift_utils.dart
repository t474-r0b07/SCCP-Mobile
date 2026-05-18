class ShiftUtils {
  static final DateTime _cycleStartDate = DateTime(2026, 2, 28);
  static const int _cycleDays = 14;
  static const int _operationalStartHour = 8;
  static const Set<int> _alfaCycleDays = {1, 4, 6, 9, 10, 12, 14};
  static const Set<int> _bravoCycleDays = {2, 3, 5, 7, 8, 11, 13};

  static final RegExp _shiftPattern = RegExp(
    r'(\d{1,2}):(\d{2})\s*(?:-|a|A)\s*(\d{1,2}):(\d{2})',
  );

  static bool isWithinShift(String? turno, {String? grupo, DateTime? now}) {
    final current = now ?? DateTime.now();
    final normalizedGroup = _normalizeGroup(grupo);
    final groupOk = normalizedGroup == null
        ? true
        : activeGroup(now: current) == normalizedGroup;

    final window = _shiftWindow(turno, now: current);
    final scheduleOk = window == null
        ? true
        : !current.isBefore(window.start) && current.isBefore(window.end);

    return groupOk && scheduleOk;
  }

  static Duration? timeUntilShiftStart(
    String? turno, {
    String? grupo,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final normalizedGroup = _normalizeGroup(grupo);
    final hasSchedule = _hasValidShiftSchedule(turno);

    if (isWithinShift(turno, grupo: grupo, now: current)) {
      return Duration.zero;
    }

    if (normalizedGroup != null && hasSchedule) {
      final next = _findNextCombinedStart(
        turno: turno!,
        normalizedGroup: normalizedGroup,
        current: current,
      );
      if (next == null) return null;
      return next.isAfter(current) ? next.difference(current) : Duration.zero;
    }

    if (normalizedGroup != null) {
      for (int i = 0; i <= _cycleDays * 2; i++) {
        final day = DateTime(
          current.year,
          current.month,
          current.day,
        ).add(Duration(days: i));
        final candidate = DateTime(
          day.year,
          day.month,
          day.day,
          _operationalStartHour,
        );
        if (!candidate.isAfter(current)) {
          continue;
        }
        if (activeGroup(now: candidate) == normalizedGroup) {
          return candidate.difference(current);
        }
      }
      return null;
    }

    final window = _shiftWindow(turno, now: current);
    if (window == null) {
      return null;
    }
    if (!current.isBefore(window.start)) {
      return Duration.zero;
    }
    return window.start.difference(current);
  }

  static String activeGroup({DateTime? now}) {
    final current = now ?? DateTime.now();
    final effectiveDay = _effectiveOperationalDay(current);
    final cycleDay = _dayInCycle(effectiveDay);
    if (_alfaCycleDays.contains(cycleDay)) {
      return 'ALFA';
    }
    if (_bravoCycleDays.contains(cycleDay)) {
      return 'BRAVO';
    }
    return 'ALFA';
  }

  static DateTime _effectiveOperationalDay(DateTime now) {
    if (now.hour < _operationalStartHour) {
      final prev = now.subtract(const Duration(days: 1));
      return DateTime(prev.year, prev.month, prev.day);
    }
    return DateTime(now.year, now.month, now.day);
  }

  static int _dayInCycle(DateTime effectiveDay) {
    final daysSinceStart = effectiveDay.difference(_cycleStartDate).inDays;
    final cycleIndex =
        ((daysSinceStart % _cycleDays) + _cycleDays) % _cycleDays;
    return cycleIndex + 1;
  }

  static String? _normalizeGroup(String? grupo) {
    if (grupo == null) return null;
    final normalized = grupo.trim().toUpperCase();
    if (normalized == 'ALFA' || normalized == 'BRAVO') {
      return normalized;
    }
    return null;
  }

  static _ShiftWindow? _shiftWindow(String? turno, {DateTime? now}) {
    final schedule = _parseShiftSchedule(turno);
    if (schedule == null) {
      return null;
    }
    final current = now ?? DateTime.now();
    var start = DateTime(
      current.year,
      current.month,
      current.day,
      schedule.startHour,
      schedule.startMinute,
    );
    var end = DateTime(
      current.year,
      current.month,
      current.day,
      schedule.endHour,
      schedule.endMinute,
    );

    final crossesMidnight = end.isBefore(start) || end.isAtSameMomentAs(start);
    if (crossesMidnight) {
      if (current.isBefore(end)) {
        start = start.subtract(const Duration(days: 1));
      } else {
        end = end.add(const Duration(days: 1));
      }
    } else if (current.isAfter(end)) {
      start = start.add(const Duration(days: 1));
      end = end.add(const Duration(days: 1));
    }

    return _ShiftWindow(start: start, end: end);
  }

  static bool _hasValidShiftSchedule(String? turno) {
    return _parseShiftSchedule(turno) != null;
  }

  static _ShiftSchedule? _parseShiftSchedule(String? turno) {
    if (turno == null || turno.trim().isEmpty) {
      return null;
    }

    final match = _shiftPattern.firstMatch(turno.trim());
    if (match == null) {
      return null;
    }

    final startHour = int.tryParse(match.group(1) ?? '');
    final startMinute = int.tryParse(match.group(2) ?? '');
    final endHour = int.tryParse(match.group(3) ?? '');
    final endMinute = int.tryParse(match.group(4) ?? '');

    if (startHour == null ||
        startMinute == null ||
        endHour == null ||
        endMinute == null) {
      return null;
    }

    return _ShiftSchedule(
      startHour: startHour,
      startMinute: startMinute,
      endHour: endHour,
      endMinute: endMinute,
    );
  }

  static DateTime? _findNextCombinedStart({
    required String turno,
    required String normalizedGroup,
    required DateTime current,
  }) {
    final schedule = _parseShiftSchedule(turno);
    if (schedule == null) return null;

    final baseDay = DateTime(current.year, current.month, current.day);
    DateTime? nextStart;

    for (int i = -1; i <= (_cycleDays * 3); i++) {
      final day = baseDay.add(Duration(days: i));
      final window = _windowForDay(day, schedule);
      if (!window.end.isAfter(current)) continue;

      final groupAnchor = DateTime(
        window.start.year,
        window.start.month,
        window.start.day,
        _operationalStartHour,
      );
      for (int j = -1; j <= 2; j++) {
        final groupStart = groupAnchor.add(Duration(days: j));
        if (activeGroup(now: groupStart) != normalizedGroup) continue;
        final groupEnd = groupStart.add(const Duration(days: 1));
        final overlapStart = _maxDateTime(
          current,
          _maxDateTime(window.start, groupStart),
        );
        final overlapEnd = _minDateTime(window.end, groupEnd);
        if (!overlapStart.isBefore(overlapEnd)) continue;
        if (nextStart == null || overlapStart.isBefore(nextStart)) {
          nextStart = overlapStart;
        }
      }
    }

    return nextStart;
  }

  static _ShiftWindow _windowForDay(DateTime day, _ShiftSchedule schedule) {
    final start = DateTime(
      day.year,
      day.month,
      day.day,
      schedule.startHour,
      schedule.startMinute,
    );
    var end = DateTime(
      day.year,
      day.month,
      day.day,
      schedule.endHour,
      schedule.endMinute,
    );
    if (!end.isAfter(start)) {
      end = end.add(const Duration(days: 1));
    }
    return _ShiftWindow(start: start, end: end);
  }

  static DateTime _maxDateTime(DateTime a, DateTime b) {
    return a.isAfter(b) ? a : b;
  }

  static DateTime _minDateTime(DateTime a, DateTime b) {
    return a.isBefore(b) ? a : b;
  }
}

class _ShiftWindow {
  final DateTime start;
  final DateTime end;

  const _ShiftWindow({
    required this.start,
    required this.end,
  });
}

class _ShiftSchedule {
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;

  const _ShiftSchedule({
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
  });
}
