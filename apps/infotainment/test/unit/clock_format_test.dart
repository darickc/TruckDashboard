import 'package:f250_infotainment/ui/presentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String at(int h, int m) => formatClock(DateTime(2026, 11, 2, h, m));

  test('12-hour with AM/PM', () {
    expect(at(0, 5), '12:05 AM', reason: 'midnight hour');
    expect(at(9, 41), '9:41 AM', reason: 'no leading zero');
    expect(at(11, 59), '11:59 AM');
    expect(at(12, 0), '12:00 PM', reason: 'noon');
    expect(at(13, 7), '1:07 PM', reason: 'minutes keep their zero');
    expect(at(23, 59), '11:59 PM');
  });
}
