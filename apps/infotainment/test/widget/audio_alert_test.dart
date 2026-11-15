import 'package:f250_infotainment/audio/audio_state.dart';
import 'package:f250_infotainment/telemetry/warnings.dart';
import 'package:f250_infotainment/ui/banner_alerts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';
import 'media_test.dart' show FakeAudio, up;

/// "Audio not playing" (bench-log 2026-11-15): audio-manager saw the call or
/// the phone's music left unlinked by WirePlumber for several seconds, and
/// the banner says so above every screen instead of staying silent. `[SIM]`.

const problem = 'The call\'s audio isn\'t connected: the audio system left it unlinked. '
    'Restarting the head unit fixes it.';

void main() {
  setUpAll(loadTestAssets);

  test('only a report with a routing problem raises it', () {
    final a = audioAlerts(up(const AudioReport(routingProblem: problem)));
    expect(a, hasLength(1));
    expect(a.single.title, 'Audio not playing');
    expect(a.single.level, AlertLevel.advisory);
    expect(a.single.detail, problem);
    expect(audioAlerts(up(const AudioReport())), isEmpty);
    expect(audioAlerts(const AudioStatus(link: AudioLink.down, detail: 'gone')), isEmpty,
        reason: 'without audio-manager the dashboard can\'t say');
  });

  testWidgets('the banner shows it while it lasts', (tester) async {
    final audio = FakeAudio()..value = up(const AudioReport());
    final h = await Harness.start(tester, audio: audio);
    await h.advance(const Duration(seconds: 1));
    expect(find.text('Audio not playing'), findsNothing);

    audio.value = up(const AudioReport(routingProblem: problem));
    await tester.pump();
    expect(find.text('Audio not playing'), findsWidgets);

    audio.value = up(const AudioReport());
    await tester.pump();
    expect(find.text('Audio not playing'), findsNothing);
  });
}
