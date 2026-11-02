import 'package:f250_infotainment/model/signal.dart';
import 'package:f250_infotainment/model/signal_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ids are unique', () {
    expect(signalsById.length, signalCatalog.length);
  });

  test('verified-on-truck signals cite their evidence', () {
    for (final s in signalCatalog.where((s) => s.provenance == Provenance.verifiedOnTruck)) {
      expect(s.evidence, contains('VERIFICATION_LOG'), reason: s.id);
    }
  });

  test('only trans temp is verified on the truck today', () {
    // Promoting another signal needs a VERIFICATION_LOG entry first; this
    // test makes that a deliberate, reviewed change.
    expect(
        signalCatalog.where((s) => s.provenance == Provenance.verifiedOnTruck).map((s) => s.id),
        ['trans_temp']);
  });

  test('computed signals reference existing, non-computed inputs', () {
    for (final s in signalCatalog.where((s) => s.isComputed)) {
      expect(s.inputs, isNotEmpty, reason: s.id);
      for (final i in s.inputs) {
        expect(signalsById[i], isNotNull, reason: '${s.id} → $i');
        expect(signalsById[i]!.isComputed, isFalse, reason: '${s.id} → $i');
      }
    }
  });

  test('plausibility ranges are well-formed', () {
    for (final s in signalCatalog) {
      expect(s.min, lessThan(s.max), reason: s.id);
    }
  });
}
