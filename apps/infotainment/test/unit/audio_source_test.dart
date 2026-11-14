import 'package:f250_infotainment/audio/audio_state.dart';
import 'package:f250_infotainment/audio/grpc_audio_source.dart';
import 'package:f250_infotainment/gen/f250/audio/v1/audio.pb.dart' as pb;
import 'package:f250_infotainment/gen/f250/audio/v1/audio.pbenum.dart' as pbe;
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';

/// f250.audio.v1 → the dashboard's model (ADR-0039), and the honesty rules
/// the client keeps even if audio-manager sent more. `[SIM]`.
void main() {
  pb.WatchAudioResponse full() => pb.WatchAudioResponse(
        bluetooth: pbe.BluetoothState.BLUETOOTH_STATE_READY,
        phone: pb.Phone(address: 'AA', name: 'Pixel 8', connected: true, paired: true),
        known: [pb.Phone(address: 'BB', name: '', paired: true)],
        nowPlaying: pb.NowPlaying(
          title: 'Song',
          artist: 'Band',
          album: 'Album',
          state: pbe.PlayState.PLAY_STATE_PAUSED,
          durationMs: 200000,
          hasPosition: true,
          positionMs: 61500,
        ),
        streaming: true,
        pairing: pb.Pairing(
          state: pbe.PairingState.PAIRING_STATE_OPEN,
          secondsLeft: 42,
          name: 'F-250',
          question: pb.PasskeyQuestion(
              id: Int64(3), phoneName: 'P2', address: 'CC', passkey: 1234, showsPasskey: true, secondsLeft: 9),
        ),
        dsp: pbe.DspState.DSP_STATE_APPLIED,
        simulated: true,
        prompts: pb.Prompts(available: true, speaking: true, musicPaused: true),
      );

  test('every field maps', () {
    final r = reportFromPb(full());
    expect(r.bluetoothReady, isTrue);
    expect(r.phone!.name, 'Pixel 8');
    expect(r.known.single.name, 'BB', reason: 'no name: the address');
    final np = r.nowPlaying!;
    expect((np.title, np.artist, np.album), ('Song', 'Band', 'Album'));
    expect(np.state, PlayState.paused);
    expect(np.duration, const Duration(seconds: 200));
    expect(np.position, const Duration(milliseconds: 61500));
    expect(r.streaming, isTrue);
    expect(r.pairing.phase, PairingPhase.open);
    expect(r.pairing.secondsLeft, 42);
    final q = r.pairing.question!;
    expect((q.id, q.passkey, q.code, q.secondsLeft), (3, 1234, '001234', 9));
    expect(r.dsp, DspPhase.applied);
    expect(r.simulated, isTrue);
    expect(r.speaking, isTrue);
    expect(r.pausedForPrompt, isTrue);
  });

  test('unknown position and duration stay unknown', () {
    final m = full()
      ..nowPlaying.hasPosition = false
      ..nowPlaying.durationMs = 0
      ..nowPlaying.state = pbe.PlayState.PLAY_STATE_UNSPECIFIED;
    final np = reportFromPb(m).nowPlaying!;
    expect(np.position, isNull);
    expect(np.duration, isNull);
    expect(np.state, PlayState.unknown);
  });

  test('a question without a code has no passkey', () {
    final m = full()..pairing.question.showsPasskey = false;
    expect(reportFromPb(m).pairing.question!.passkey, isNull);
  });

  test('no track without a connected phone, nothing at all without Bluetooth', () {
    final noPhone = full()..clearPhone();
    final r = reportFromPb(noPhone);
    expect(r.phone, isNull);
    expect(r.nowPlaying, isNull, reason: 'a track without its phone is never current');
    expect(r.streaming, isFalse);

    final disconnected = full()..phone.connected = false;
    expect(reportFromPb(disconnected).nowPlaying, isNull);

    expect(reportFromPb(noPhone).pausedForPrompt, isFalse, reason: 'no phone, nothing paused');

    final down = full()..bluetooth = pbe.BluetoothState.BLUETOOTH_STATE_UNAVAILABLE;
    final d = reportFromPb(down);
    expect(d.bluetoothReady, isFalse);
    expect(d.phone, isNull);
    expect(d.nowPlaying, isNull);
    expect(d.known, isEmpty);
  });

  test('the last phone and a connection attempt map; nothing of them without Bluetooth', () {
    final m = full()
      ..known.clear()
      ..known.add(pb.Phone(address: 'BB', name: '', paired: true, last: true))
      ..connect = pb.ConnectAttempt(address: 'BB', name: '', automatic: true, detail: 'x');
    final r = reportFromPb(m);
    expect(r.known.single.last, isTrue);
    expect(r.known.single.name, 'BB', reason: 'no name: the address');
    expect(r.connect.busy, isTrue);
    expect(r.connect.name, 'BB');
    expect(r.connect.automatic, isTrue);
    expect(r.connect.detail, 'x');
    expect(r.paired.map((p) => p.address), ['AA', 'BB'], reason: 'the connected phone first');
    m.bluetooth = pbe.BluetoothState.BLUETOOTH_STATE_UNAVAILABLE;
    final d = reportFromPb(m);
    expect(d.connect.busy, isFalse);
    expect(d.known, isEmpty);
  });

  test('speaker limits check', () {
    const l = SpeakerLimits();
    expect(l.check(const SpeakerSettings()), isNull);
    expect(l.check(const SpeakerSettings(fader: 11)), contains('Fader'));
    expect(l.check(const SpeakerSettings(subLevelDb: 7)), contains('Sub'));
    expect(l.check(const SpeakerSettings(crossoverHz: 40)), contains('Crossover'));
  });

  test('track times', () {
    expect(formatTrackTime(const Duration(seconds: 5)), '0:05');
    expect(formatTrackTime(const Duration(minutes: 3, seconds: 5)), '3:05');
    expect(formatTrackTime(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
  });

  group('calls (ADR-0045)', () {
    pb.WatchAudioResponse withCall(pbe.CallState state) => full()
      ..calls = pb.Calls(
        available: true,
        phoneName: 'Pixel 8',
        otherCalls: 1,
        micMuted: true,
        call: pb.Call(
            id: Int64(7), state: state, number: '+15550100', name: 'Test Caller', activeS: 65, multiparty: true),
      );

    test('a call maps', () {
      final c = reportFromPb(withCall(pbe.CallState.CALL_STATE_ACTIVE)).calls!;
      expect(c.available, isTrue);
      expect(c.phoneName, 'Pixel 8');
      expect((c.otherCalls, c.micMuted), (1, true));
      final call = c.call!;
      expect((call.id, call.phase, call.number, call.name), (7, CallPhase.active, '+15550100', 'Test Caller'));
      expect(call.active, const Duration(seconds: 65));
      expect(call.multiparty, isTrue);
      expect((call.caller, call.secondLine), ('Test Caller', '+15550100'));
      for (final (st, phase) in [
        (pbe.CallState.CALL_STATE_INCOMING, CallPhase.incoming),
        (pbe.CallState.CALL_STATE_WAITING, CallPhase.waiting),
        (pbe.CallState.CALL_STATE_DIALING, CallPhase.dialing),
        (pbe.CallState.CALL_STATE_ALERTING, CallPhase.alerting),
        (pbe.CallState.CALL_STATE_HELD, CallPhase.held),
      ]) {
        expect(reportFromPb(withCall(st)).call!.phase, phase);
      }
    });

    test('who is calling, when the phone gives less', () {
      expect(const PhoneCall(id: 1, phase: CallPhase.incoming, number: '+1555').caller, '+1555');
      expect(const PhoneCall(id: 1, phase: CallPhase.incoming, number: '+1555').secondLine, '');
      expect(const PhoneCall(id: 1, phase: CallPhase.incoming, withheld: true).caller, 'Number withheld');
      expect(const PhoneCall(id: 1, phase: CallPhase.incoming).caller, 'Unknown caller');
    });

    test('no call without a connected phone, an unknown state, or calls at all', () {
      final gone = withCall(pbe.CallState.CALL_STATE_INCOMING)..phone.connected = false;
      final r = reportFromPb(gone);
      expect(r.calls, isNotNull);
      expect(r.call, isNull, reason: 'a gone phone\'s call is never shown');
      expect(r.calls!.micMuted, isFalse);
      expect(reportFromPb(withCall(pbe.CallState.CALL_STATE_UNSPECIFIED)).call, isNull);
      expect(reportFromPb(full()).calls, isNull, reason: 'an audio-manager without calls');
      final off = full()..calls = pb.Calls(detail: 'Calls stay on the phone: no call microphone is configured.');
      final c = reportFromPb(off).calls!;
      expect((c.available, c.call), (false, null));
      expect(c.detail, startsWith('Calls stay on the phone'));
    });
  });
}
