import 'signal.dart';

/// The signals the UI knows about in Phase 2.
///
/// Provenance and requests mirror docs/diagnostics/FORD_6_0_PIDS.md exactly.
/// Nothing here is new information about the truck. In Phase 3 the gateway
/// serves these definitions from the signal registry (shared/signals/), and
/// this file goes away.
const verificationLog = 'docs/diagnostics/VERIFICATION_LOG.md';

double _delta(List<double> v) => v[0] - v[1];

const signalCatalog = <SignalDef>[
  SignalDef(
    id: 'rpm', name: 'Engine speed', shortName: 'RPM',
    quantity: Quantity.rotation, unit: 'rpm', provenance: Provenance.sae,
    min: 0, max: 5000, request: '01 0C',
    staleAfter: Duration(milliseconds: 1500),
  ),
  SignalDef(
    id: 'speed', name: 'Vehicle speed', shortName: 'Speed',
    quantity: Quantity.speed, unit: 'km/h', provenance: Provenance.sae,
    min: 0, max: 255, request: '01 0D',
    staleAfter: Duration(seconds: 2),
  ),
  SignalDef(
    id: 'ect', name: 'Engine coolant temp', shortName: 'ECT',
    quantity: Quantity.temperature, unit: 'degC', provenance: Provenance.sae,
    min: -40, max: 150, request: '01 05',
    staleAfter: Duration(seconds: 4),
  ),
  SignalDef(
    id: 'eot', name: 'Engine oil temp', shortName: 'EOT',
    quantity: Quantity.temperature, unit: 'degC',
    provenance: Provenance.importedUnverified,
    min: -40, max: 150, request: '22 13 10', responder: '7E8',
    staleAfter: Duration(seconds: 4),
  ),
  SignalDef(
    id: 'eot_ect_delta', name: 'EOT − ECT', shortName: 'EOT−ECT',
    quantity: Quantity.temperatureDelta, unit: 'degC',
    provenance: Provenance.computed,
    min: -40, max: 80, inputs: ['eot', 'ect'], compute: _delta,
  ),
  SignalDef(
    id: 'trans_temp', name: 'Transmission fluid temp', shortName: 'Trans',
    quantity: Quantity.temperature, unit: 'degC',
    provenance: Provenance.verifiedOnTruck,
    min: -40, max: 150, request: '22 16 74', responder: '7E9',
    evidence: '$verificationLog (2026-08-09)',
    staleAfter: Duration(seconds: 4),
  ),
  SignalDef(
    id: 'map', name: 'Manifold absolute pressure', shortName: 'MAP',
    quantity: Quantity.pressure, unit: 'kPa',
    provenance: Provenance.importedUnverified,
    min: 0, max: 400, request: '22 14 40',
    staleAfter: Duration(milliseconds: 1500),
  ),
  SignalDef(
    id: 'baro', name: 'Barometric pressure', shortName: 'Baro',
    quantity: Quantity.pressure, unit: 'kPa', provenance: Provenance.sae,
    min: 50, max: 110, request: '01 33',
    staleAfter: Duration(seconds: 20),
  ),
  SignalDef(
    id: 'boost', name: 'Boost (MAP − baro)', shortName: 'Boost',
    quantity: Quantity.pressure, unit: 'kPa', provenance: Provenance.computed,
    min: -20, max: 300, inputs: ['map', 'baro'], compute: _delta,
    // Baro is polled slowly and barely changes; allow it to be older.
    maxInputSkew: Duration(seconds: 20),
  ),
  SignalDef(
    id: 'iat', name: 'Intake air temp', shortName: 'IAT',
    quantity: Quantity.temperature, unit: 'degC', provenance: Provenance.sae,
    min: -40, max: 120, request: '01 0F',
    staleAfter: Duration(seconds: 8),
  ),
  SignalDef(
    id: 'load', name: 'Engine load', shortName: 'Load',
    quantity: Quantity.percent, unit: '%', provenance: Provenance.sae,
    min: 0, max: 100, request: '01 04',
    staleAfter: Duration(seconds: 2),
  ),
  SignalDef(
    id: 'icp', name: 'Injection control pressure', shortName: 'ICP',
    quantity: Quantity.pressure, unit: 'kPa',
    provenance: Provenance.importedUnverified,
    min: 0, max: 31000, request: '22 14 46', displayDecimals: 0,
    staleAfter: Duration(seconds: 2),
  ),
  SignalDef(
    id: 'ipr_duty', name: 'IPR duty cycle', shortName: 'IPR',
    quantity: Quantity.percent, unit: '%',
    provenance: Provenance.importedUnverified,
    min: 0, max: 100, request: '22 14 34',
    staleAfter: Duration(seconds: 2),
  ),
  SignalDef(
    id: 'ficm_main', name: 'FICM main power', shortName: 'FICM',
    quantity: Quantity.voltage, unit: 'V',
    provenance: Provenance.importedUnverified,
    min: 0, max: 60, request: '22 09 D0',
    staleAfter: Duration(seconds: 4),
  ),
  SignalDef(
    id: 'battery', name: 'Battery voltage', shortName: 'Battery',
    quantity: Quantity.voltage, unit: 'V',
    provenance: Provenance.importedUnverified,
    min: 0, max: 20, request: '22 11 72',
    staleAfter: Duration(seconds: 8),
  ),
  SignalDef(
    // Torque export row "[FORD]Fuel Level", 0x2216C1, ((A*256)+B)/328 %.
    // Unverified: which module answers, and whether the scaling matches the
    // cluster gauge, are open questions (TRUCK_SESSION.md Part 3).
    id: 'fuel_level', name: 'Fuel level', shortName: 'Fuel',
    quantity: Quantity.percent, unit: '%',
    provenance: Provenance.importedUnverified,
    min: 0, max: 100, request: '22 16 C1',
    staleAfter: Duration(seconds: 15),
  ),
  SignalDef(
    id: 'egt', name: 'Exhaust gas temp', shortName: 'EGT',
    quantity: Quantity.temperature, unit: 'degC',
    provenance: Provenance.auxSensor,
    min: -40, max: 1000,
    enabled: false, disabledReason: 'No EGT probe installed',
  ),
];

final signalsById = {for (final s in signalCatalog) s.id: s};
