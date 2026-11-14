import 'package:flutter/material.dart';

import '../../audio/audio_state.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/audio_button.dart';
import '../widgets/panel.dart';
import '../widgets/tap_target.dart';

/// Phones (ADR-0039), opened from Media: on the left every paired phone,
/// with Connect for the ones not connected (one phone at a time: connecting
/// one disconnects the other), Disconnect for the connected one, and Delete
/// (asked again in the row: the phone must then be paired again); on the
/// right the pairing window for a new
/// phone (Pair, its countdown, and the phone's code to confirm).
/// audio-manager also reconnects the phone connected last by itself for a
/// while; the list says which one that is. Everything comes from
/// services/audio-manager; without it nothing is shown as current.
class PhonesScreen extends StatefulWidget {
  const PhonesScreen({super.key});

  @override
  State<PhonesScreen> createState() => _PhonesScreenState();
}

class _PhonesScreenState extends State<PhonesScreen> {
  /// What the last tap did, when it didn't work.
  String? _message;
  bool _busy = false;

  /// The phone whose Delete was tapped: its row asks again.
  String? _confirmDelete;

  Future<void> _run(Future<CommandResult> Function() f) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final r = await f();
      if (mounted) setState(() => _message = r.ok ? null : r.detail);
    } catch (e) {
      if (mounted) setState(() => _message = 'audio-manager didn\'t answer: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final audio = AppScope.of(context).audio;
    return ValueListenableBuilder<AudioStatus>(
      valueListenable: audio.status,
      builder: (context, status, _) {
        final r = status.report;
        if (r == null) return _noService(status);
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _list(r, audio)),
          const SizedBox(width: kGap),
          SizedBox(width: 270, child: _pairPanel(r, audio)),
        ]);
      },
    );
  }

  Widget _noService(AudioStatus s) {
    final p = Palette.of(context);
    return Panel(
      child: Center(
        child: Text(
            '${s.link == AudioLink.connecting ? 'Connecting to audio-manager…' : 'audio-manager not connected'}'
            '${s.detail == null ? '' : ' (${s.detail})'}. No phone or pairing window is shown until it answers.',
            key: const ValueKey('phones-link'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, color: p.advisory)),
      ),
    );
  }

  Widget _list(AudioReport r, AudioSource audio) {
    final p = Palette.of(context);
    final phones = r.paired;
    final c = r.connect;
    final String? note = _message ??
        (c.busy
            ? (c.automatic ? 'Trying ${c.name} again by itself…' : 'Connecting to ${c.name}…')
            : (c.detail.isEmpty ? null : c.detail));
    return Panel(
      title: 'Paired phones',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: !r.bluetoothReady
              ? Text(r.bluetoothDetail.isEmpty ? 'Bluetooth unavailable.' : r.bluetoothDetail,
                  key: const ValueKey('phones-empty'), style: TextStyle(fontSize: 16, color: p.advisory))
              : phones.isEmpty
                  ? Text('No phones paired yet. Tap Pair a phone, then pick '
                      '${r.pairing.name.isEmpty ? 'this head unit' : r.pairing.name} in the phone\'s Bluetooth settings.',
                      key: const ValueKey('phones-empty'), style: TextStyle(fontSize: 16, color: p.textDim))
                  : ListView.separated(
                      itemCount: phones.length,
                      separatorBuilder: (_, _) => Divider(height: 9, color: p.border),
                      itemBuilder: (context, i) => _row(phones[i], r, audio),
                    ),
        ),
        if (note != null) ...[
          const SizedBox(height: 6),
          Text(note,
              key: const ValueKey('phones-detail'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 14, color: _message != null || (!c.busy && c.detail.isNotEmpty) ? p.advisory : p.text)),
        ],
        // Where calls go (ADR-0045): only from an audio-manager that has
        // calls, and only with a phone connected.
        if (r.calls != null && r.phone != null) ...[
          const SizedBox(height: 6),
          Text(
              r.calls!.available
                  ? 'Calls on ${r.phone!.name} come to the truck.'
                  : (r.calls!.detail.isEmpty ? 'Calls stay on the phone.' : r.calls!.detail),
              key: const ValueKey('phones-calls'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: p.textDim)),
        ],
      ]),
    );
  }

  Widget _row(Phone ph, AudioReport r, AudioSource audio) {
    final p = Palette.of(context);
    final connecting = r.connect.busy && r.connect.address == ph.address;
    final status = ph.connected
        ? 'Connected'
        : connecting
            ? (r.connect.automatic ? 'Reconnecting by itself…' : 'Connecting…')
            : ph.last
                ? 'Last used'
                : 'Not connected';
    final canConnect = !ph.connected && !r.connect.busy && !_busy && r.bluetoothReady;
    if (_confirmDelete == ph.address) return _confirmRow(ph, audio);
    final idle = !_busy && r.bluetoothReady && !connecting;
    return SizedBox(
      key: ValueKey('phones-row-${ph.address}'),
      height: kMinTouch + 4,
      child: Row(children: [
        Icon(ph.connected ? Icons.bluetooth_connected_rounded : Icons.smartphone_rounded,
            size: 28, color: ph.connected ? p.accent : p.textDim),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(ph.name,
                key: ValueKey('phones-name-${ph.address}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text)),
            Text(status,
                key: ValueKey('phones-status-${ph.address}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: ph.connected ? p.ok : p.textDim)),
          ]),
        ),
        const SizedBox(width: kGap),
        SizedBox(
          width: 176,
          child: ph.connected
              ? AudioButton(
                  key: ValueKey('phones-disconnect-${ph.address}'),
                  text: 'Disconnect',
                  icon: Icons.bluetooth_disabled_rounded,
                  onTap: idle ? () => _run(() => audio.disconnectPhone(ph.address)) : null,
                )
              : AudioButton(
                  key: ValueKey('phones-connect-${ph.address}'),
                  text: connecting ? 'Connecting…' : 'Connect',
                  icon: Icons.bluetooth_searching_rounded,
                  onTap: canConnect ? () => _run(() => audio.connectPhone(ph.address)) : null,
                ),
        ),
        const SizedBox(width: kGap),
        Opacity(
          opacity: idle ? 1 : 0.45,
          child: TapTarget(
            key: ValueKey('phones-delete-${ph.address}'),
            label: idle ? 'Delete ${ph.name}' : 'Delete ${ph.name} (unavailable)',
            padding: EdgeInsets.zero,
            onTap: idle ? () => setState(() => _confirmDelete = ph.address) : () {},
            child: Icon(Icons.delete_outline_rounded, size: 28, color: p.text),
          ),
        ),
      ]),
    );
  }

  /// Delete, asked again: the phone has to be paired again afterwards.
  Widget _confirmRow(Phone ph, AudioSource audio) {
    final p = Palette.of(context);
    return SizedBox(
      key: ValueKey('phones-confirm-${ph.address}'),
      height: kMinTouch + 4,
      child: Row(children: [
        Icon(Icons.delete_outline_rounded, size: 28, color: p.advisory),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('Delete ${ph.name}?',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
            Text('Pair it again to use it.',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p.textDim)),
          ]),
        ),
        const SizedBox(width: kGap),
        SizedBox(
          width: 130,
          child: AudioButton(
            key: ValueKey('phones-delete-yes-${ph.address}'),
            text: 'Delete',
            icon: Icons.delete_rounded,
            emphasis: true,
            onTap: _busy
                ? null
                : () {
                    setState(() => _confirmDelete = null);
                    _run(() => audio.forgetPhone(ph.address));
                  },
          ),
        ),
        const SizedBox(width: kGap),
        SizedBox(
          width: 116,
          child: AudioButton(
            key: ValueKey('phones-delete-no-${ph.address}'),
            text: 'Keep',
            icon: Icons.close_rounded,
            onTap: () => setState(() => _confirmDelete = null),
          ),
        ),
      ]),
    );
  }

  Widget _pairPanel(AudioReport r, AudioSource audio) {
    final p = Palette.of(context);
    final pairing = r.pairing;
    final q = pairing.question;
    if (q != null) return _question(q, audio);
    final open = pairing.open;
    final String windowText = switch (pairing.phase) {
      PairingPhase.open =>
        'Visible as "${pairing.name}" for ${formatTrackTime(Duration(seconds: pairing.secondsLeft))}. Pick it in the phone\'s Bluetooth settings.',
      PairingPhase.opening => 'Opening the pairing window…',
      PairingPhase.closing => 'Closing the pairing window…',
      PairingPhase.failed => pairing.detail,
      PairingPhase.closed => pairing.detail.isEmpty
          ? 'Not visible to new phones. Pairing opens only from here, and closes by itself.'
          : pairing.detail,
    };
    return Panel(
      title: 'A new phone',
      child: ListView(children: [
        AudioButton(
          key: const ValueKey('phones-pair'),
          text: open
              ? (pairing.phase == PairingPhase.open
                  ? 'Stop pairing · ${formatTrackTime(Duration(seconds: pairing.secondsLeft))}'
                  : 'Stop pairing')
              : 'Pair a phone',
          icon: open ? Icons.bluetooth_disabled_rounded : Icons.bluetooth_searching_rounded,
          onTap: !r.bluetoothReady || _busy || pairing.phase == PairingPhase.closing
              ? null
              : open
                  ? () => _run(() async => CommandResult(ok: await audio.closePairing()))
                  : () => _run(() => audio.openPairing()),
          emphasis: open,
        ),
        const SizedBox(height: 8),
        Text(windowText,
            key: const ValueKey('phones-pairing'),
            style: TextStyle(
                fontSize: 15, color: pairing.phase == PairingPhase.failed ? p.advisory : (open ? p.text : p.textDim))),
      ]),
    );
  }

  Widget _question(PasskeyQuestion q, AudioSource audio) {
    final p = Palette.of(context);
    return Container(
      key: const ValueKey('phones-question'),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.accent, width: 2),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${q.phoneName} wants to pair',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.text)),
        const SizedBox(height: 6),
        if (q.passkey != null) ...[
          Text('Does the phone show this code?', style: TextStyle(fontSize: 15, color: p.textDim)),
          Text('${q.code.substring(0, 3)} ${q.code.substring(3)}',
              key: const ValueKey('phones-passkey'),
              style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: 2, color: p.text)),
        ] else
          Text('It shows no code. Accept only if it is the phone in your hand.',
              style: TextStyle(fontSize: 15, color: p.advisory)),
        Text('Refused by itself in ${q.secondsLeft} s.', style: TextStyle(fontSize: 13, color: p.textDim)),
        const Spacer(),
        AudioButton(
            key: const ValueKey('phones-confirm-yes'),
            text: q.passkey != null ? 'Yes, it matches' : 'Accept',
            icon: Icons.check_rounded,
            onTap: _busy ? null : () => _run(() => audio.confirm(q.id, true)),
            emphasis: true),
        const SizedBox(height: kGap),
        AudioButton(
            key: const ValueKey('phones-confirm-no'),
            text: 'No',
            icon: Icons.close_rounded,
            onTap: _busy ? null : () => _run(() => audio.confirm(q.id, false))),
      ]),
    );
  }
}
