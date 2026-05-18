import 'package:flutter_test/flutter_test.dart';
import 'package:sccp_mobile/core/utils/distance_calculator.dart';

void main() {
  group('DistanceCalculator', () {
    test('returns zero for same coordinate', () {
      final distance = DistanceCalculator.calculateDistance(
        -21.521201,
        -64.740599,
        -21.521201,
        -64.740599,
      );

      expect(distance, 0);
    });

    test('is symmetric', () {
      final ab = DistanceCalculator.calculateDistance(
        -21.521201,
        -64.740599,
        -21.534034,
        -64.737505,
      );
      final ba = DistanceCalculator.calculateDistance(
        -21.534034,
        -64.737505,
        -21.521201,
        -64.740599,
      );

      expect((ab - ba).abs(), lessThan(0.0001));
    });

    test('matches expected magnitude for one degree latitude', () {
      final distance = DistanceCalculator.calculateDistance(
        0,
        0,
        1,
        0,
      );

      expect(distance, greaterThan(110000));
      expect(distance, lessThan(112000));
    });
  });
}
