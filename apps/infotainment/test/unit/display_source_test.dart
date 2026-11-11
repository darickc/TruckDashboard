import 'dart:async';
import 'dart:io';

import 'package:f250_infotainment/core/settings.dart';
import 'package:f250_infotainment/data/gateway_connection.dart';
import 'package:f250_infotainment/display/display_state.dart';
import 'package:f250_infotainment/display/grpc_display_source.dart';
import 'package:f250_infotainment/gen/f250/power/v1/display.pbgrpc.dart' as pb;
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart' as grpc;

/// A stand-in power-manager: streams the states the test pushes and applies
/// SetDisplay to its own state, as power-manager does.
class FakePowerManager extends pb.DisplayServiceBase {
  var updates = StreamController<pb.WatchDisplayResponse>.broadcast();
  final sets = <pb.SetDisplayRequest>[];
  pb.Display current = pb.Display(
    mode: pb.DisplayMode.DISPLAY_MODE_NIGHT,
    choice: pb.DisplayChoice.DISPLAY_CHOICE_AUTO,
    basis: pb.ModeBasis.MODE_BASIS_SUN,
    sun: pb.SunStatus.SUN_STATUS_KNOWN,
    sunElevationDeg: -9.5,
    dayBrightnessPct: 100,
    nightBrightnessPct: 40,
    minBrightnessPct: 10,
    backlightPresent: true,
    backlight: '10-0045',
    brightnessPct: 40,
  );

  void push(pb.Display d) {
    current = d;
    updates.add(pb.WatchDisplayResponse(display: d));
  }

  @override
  Stream<pb.WatchDisplayResponse> watchDisplay(
      grpc.ServiceCall call, pb.WatchDisplayRequest request) async* {
    yield pb.WatchDisplayResponse(display: current);
    yield* updates.stream;
  }

  @override
  Future<pb.SetDisplayResponse> setDisplay(grpc.ServiceCall call, pb.SetDisplayRequest r) async {
    sets.add(r);
    final d = current.deepCopy();
    if (r.choice == pb.DisplayChoice.DISPLAY_CHOICE_DAY) {
      d
        ..choice = r.choice
        ..mode = pb.DisplayMode.DISPLAY_MODE_DAY
        ..basis = pb.ModeBasis.MODE_BASIS_MANUAL;
    }
    if (r.nightBrightnessPct != 0) d.nightBrightnessPct = r.nightBrightnessPct;
    current = d;
    return pb.SetDisplayResponse(display: d);
  }
}

Future<grpc.Server> serve(FakePowerManager fake, String path) async {
  final server = grpc.Server.create(services: [fake]);
  await server.serve(address: InternetAddress(path, type: InternetAddressType.unix), port: 0);
  return server;
}

Future<DisplayStatus> until(GrpcDisplaySource src, bool Function(DisplayStatus) pred) async {
  if (pred(src.status.value)) return src.status.value;
  final done = Completer<DisplayStatus>();
  void check() {
    if (!done.isCompleted && pred(src.status.value)) done.complete(src.status.value);
  }

  src.status.addListener(check);
  try {
    return await done.future.timeout(const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('last status ${src.status.value}'));
  } finally {
    src.status.removeListener(check);
  }
}

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('f250-pm');
    path = '${dir.path}/p.sock';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('follows power-manager, sends changes, and holds the theme when it goes', () async {
    final fake = FakePowerManager();
    final server = await serve(fake, path);
    final src = GrpcDisplaySource(
        endpoint: UnixEndpoint(path), retryDelay: const Duration(milliseconds: 100))
      ..start();

    var s = await until(src, (s) => s.link == DisplayLink.connected);
    expect(s.mode, DayNight.night);
    expect(s.choice, DisplayChoice.auto);
    expect(s.report!.basis, ModeBasis.sun);
    expect(s.report!.sunElevationDeg, -9.5);
    expect(s.pct, 40);
    expect(s.canAuto, isTrue);
    expect(describeMode(s), 'Auto: Night by the sun (sun −9.5°).');

    await src.setChoice(DisplayChoice.day);
    expect(fake.sets.single.choice, pb.DisplayChoice.DISPLAY_CHOICE_DAY);
    expect(fake.sets.single.source, 'dashboard');
    s = src.status.value;
    expect(s.mode, DayNight.day);
    expect(s.report!.basis, ModeBasis.manual);

    await src.setBrightness(DayNight.night, 25);
    expect(fake.sets.last.nightBrightnessPct, 25);
    expect(fake.sets.last.dayBrightnessPct, 0, reason: 'only the one level');
    expect(src.status.value.nightPct, 25);

    // power-manager stops: the theme stays as it was, nothing is claimed.
    fake.updates.addError(const grpc.GrpcError.unavailable('power-manager stopping'));
    s = await until(src, (s) => s.link == DisplayLink.lost);
    expect(s.mode, DayNight.day);
    expect(s.report, isNull);
    expect(s.pct, isNull);
    expect(s.canAuto, isFalse);
    expect(describeMode(s), contains('power-manager not connected (power-manager stopping)'));

    // Night for the screen alone while it is away; Auto does nothing.
    await src.setChoice(DisplayChoice.auto);
    expect(src.status.value.mode, DayNight.day);
    await src.setChoice(DisplayChoice.night);
    expect(src.status.value.mode, DayNight.night);
    expect(src.status.value.choice, DisplayChoice.night);
    expect(() => src.setBrightness(DayNight.night, 50), throwsStateError);

    // Back: power-manager's state replaces the local choice.
    fake.updates = StreamController<pb.WatchDisplayResponse>.broadcast();
    s = await until(src, (s) => s.link == DisplayLink.connected);
    expect(s.mode, DayNight.day);
    expect(s.choice, DisplayChoice.day);

    src.stop();
    await server.shutdown();
  });

  test('never connected: Day, saying so', () async {
    final src = GrpcDisplaySource(
        endpoint: UnixEndpoint('${dir.path}/nobody.sock'),
        retryDelay: const Duration(milliseconds: 100))
      ..start();
    final s = await until(src, (s) => s.link == DisplayLink.lost);
    expect(s.mode, DayNight.day);
    expect(describeMode(s), startsWith('power-manager not connected'));
    src.stop();
  });

  test('reports map from the API; unknown values never claim the sun', () {
    expect(reportFromPb(pb.Display()), isNull, reason: 'undecided');
    final r = reportFromPb(pb.Display(
      mode: pb.DisplayMode.DISPLAY_MODE_DAY,
      basis: pb.ModeBasis.valueOf(99) ?? pb.ModeBasis.MODE_BASIS_UNSPECIFIED,
      sun: pb.SunStatus.SUN_STATUS_UNSPECIFIED,
      sunElevationDeg: 30,
    ))!;
    expect(r.mode, DayNight.day);
    expect(r.basis, ModeBasis.fallback);
    expect(r.sun, SunStatus.clockNotSynchronized);
    expect(r.sunElevationDeg, isNull, reason: 'only with a known sun');
    expect(r.backlight, isNull);
    expect(r.choice, DisplayChoice.auto);

    final clockNotSet = reportFromPb(pb.Display(
        mode: pb.DisplayMode.DISPLAY_MODE_NIGHT,
        basis: pb.ModeBasis.MODE_BASIS_FALLBACK,
        sun: pb.SunStatus.SUN_STATUS_CLOCK_NOT_SET))!;
    expect(
        describeMode(DisplayStatus(
            link: DisplayLink.connected,
            mode: clockNotSet.mode,
            choice: clockNotSet.choice,
            report: clockNotSet)),
        'Auto unavailable: clock not set. Showing Night.');
  });

  test('choices map to the API', () {
    expect(choiceToPb(DisplayChoice.auto), pb.DisplayChoice.DISPLAY_CHOICE_AUTO);
    expect(choiceToPb(DisplayChoice.day), pb.DisplayChoice.DISPLAY_CHOICE_DAY);
    expect(choiceToPb(DisplayChoice.night), pb.DisplayChoice.DISPLAY_CHOICE_NIGHT);
  });
}
