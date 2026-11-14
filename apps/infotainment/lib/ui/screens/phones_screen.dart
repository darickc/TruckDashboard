import 'dart:async';

import 'package:flutter/material.dart';

import '../../audio/audio_state.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/audio_button.dart';
import '../widgets/call_bar.dart';
import '../widgets/panel.dart';
import '../widgets/tap_target.dart';
import 'phone_lists.dart';

/// The Phone screen (ADR-0045 phase 2), opened from Home (and from Media's
/// Phones button, on the paired phones): the connected phone's contacts and
/// recent calls to call from, a keypad (only when stopped), and the paired
/// phones. During a call it shows the call instead, large (CallBar.large),
/// and the bar over the top of the screen is hidden here; while a phone asks
/// to pair, the paired phones and the question, without the views' row.
///
/// The phone's lists come from audio-manager, which reads them over PBAP
/// when the phone connects; they are fetched again whenever their version
/// changes, and never shown for a phone that has gone.
class PhonesScreen extends StatefulWidget {
  const PhonesScreen({super.key});

  @override
  State<PhonesScreen> createState() => _PhonesScreenState();
}

const _tabLabels = {
  PhoneTab.contacts: 'Contacts',
  PhoneTab.recent: 'Recent',
  PhoneTab.keypad: 'Keypad',
  PhoneTab.phones: 'Phones',
};

const _tabIcons = {
  PhoneTab.contacts: Icons.contacts_rounded,
  PhoneTab.recent: Icons.history_rounded,
  PhoneTab.keypad: Icons.dialpad_rounded,
  PhoneTab.phones: Icons.bluetooth_rounded,
};

class _PhonesScreenState extends State<PhonesScreen> {
  late AudioSource _audio;
  PhonebookData _data = const PhonebookData(version: -1);
  int? _fetching;
  String _fetchError = '';

  /// What the last call request answered, when it wasn't done.
  String _note = '';
  Timer? _clearNote;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _audio = AppScope.of(context).audio;
    _audio.status.removeListener(_onStatus);
    _audio.status.addListener(_onStatus);
    _onStatus();
  }

  @override
  void dispose() {
    _audio.status.removeListener(_onStatus);
    _clearNote?.cancel();
    super.dispose();
  }

  /// Fetches the lists when their version changes; drops them with the
  /// phone.
  void _onStatus() {
    final r = _audio.status.value.report;
    final b = r?.phonebook;
    if (r == null || r.phone == null || b == null || b.phase == PhonebookPhase.none) {
      if (_data.contacts.isNotEmpty || _data.recent.isNotEmpty) {
        setState(() => _data = const PhonebookData(version: -1));
      }
      return;
    }
    if (b.version == _data.version || b.version == _fetching) return;
    if (b.phase != PhonebookPhase.ready && b.phase != PhonebookPhase.loading) return;
    _fetch(b.version);
  }

  Future<void> _fetch(int version) async {
    _fetching = version;
    try {
      final d = await _audio.phonebook();
      if (!mounted) return;
      setState(() {
        _data = d;
        _fetchError = '';
      });
    } catch (e) {
      if (mounted) setState(() => _fetchError = 'audio-manager didn\'t send the lists: $e');
    } finally {
      _fetching = null;
    }
  }

  /// Places a call; true when the phone took it.
  Future<bool> _dial(String number) async {
    CommandResult r;
    try {
      r = await _audio.dial(number);
    } catch (e) {
      r = CommandResult(ok: false, detail: 'audio-manager didn\'t answer: $e');
    }
    if (!mounted) return r.ok;
    _clearNote?.cancel();
    setState(() => _note = r.ok ? '' : r.detail);
    if (!r.ok) {
      _clearNote = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _note = '');
      });
    }
    return r.ok;
  }

  Future<void> _refresh() async {
    try {
      final r = await _audio.refreshPhonebook();
      if (mounted && !r.ok) setState(() => _note = r.detail);
    } catch (e) {
      if (mounted) setState(() => _note = 'audio-manager didn\'t answer: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ValueListenableBuilder<AudioStatus>(
      valueListenable: _audio.status,
      builder: (context, status, _) {
        final r = status.link == AudioLink.up ? status.report : null;
        // A call takes the whole screen: what it is, who, and its buttons.
        if (r?.call != null) return CallBar(audio: _audio, large: true);
        // So does a phone asking to pair (its code to compare, Yes and No),
        // whichever view was showing.
        if (r?.pairing.question != null) return const PhoneDevicesView();
        return ValueListenableBuilder<PhoneTab>(
          valueListenable: s.phoneTab,
          builder: (context, tab, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: kMinTouch,
              child: Row(children: [
                for (final (i, t) in PhoneTab.values.indexed) ...[
                  if (i > 0) const SizedBox(width: kGap),
                  Expanded(child: _tab(t, tab == t, s)),
                ],
              ]),
            ),
            const SizedBox(height: kGap),
            Expanded(
              child: r == null && tab != PhoneTab.phones
                  ? _noService(status)
                  : switch (tab) {
                      PhoneTab.phones => const PhoneDevicesView(),
                      PhoneTab.contacts => ContactsView(
                          report: r!, data: _data, fetchError: _fetchError, note: _note, onDial: _dial, onRefresh: _refresh),
                      PhoneTab.recent => RecentView(
                          report: r!, data: _data, fetchError: _fetchError, note: _note, onDial: _dial, onRefresh: _refresh),
                      PhoneTab.keypad => KeypadView(report: r!, note: _note, onDial: _dial),
                    },
            ),
          ]),
        );
      },
    );
  }

  Widget _tab(PhoneTab t, bool selected, AppServices s) {
    final p = Palette.of(context);
    return TapTarget(
      key: ValueKey('phone-tab-${t.name}'),
      label: _tabLabels[t]!,
      selected: selected,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      onTap: () => s.phoneTab.value = t,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_tabIcons[t], size: 24, color: p.text),
          const SizedBox(width: 6),
          Text(_tabLabels[t]!, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text)),
        ]),
      ),
    );
  }

  Widget _noService(AudioStatus s) {
    final p = Palette.of(context);
    return Panel(
      child: Center(
        child: Text(
            '${s.link == AudioLink.connecting ? 'Connecting to audio-manager…' : 'audio-manager not connected'}'
            '${s.detail == null ? '' : ' (${s.detail})'}. No phone, contact or call is shown until it answers.',
            key: const ValueKey('phone-link'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, color: p.advisory)),
      ),
    );
  }
}

/// The paired phones (ADR-0039), the Phone screen's Phones view: on the left
/// every paired phone, with Connect for the ones not connected (one phone at
/// a time: connecting one disconnects the other), Disconnect for the
/// connected one, and Delete (asked again in the row: the phone must then
/// be paired again); on the right the pairing window for a new phone (Pair,
/// its countdown, and the phone's code to confirm). audio-manager also
/// reconnects the phone connected last by itself for a while; the list says
/// which one that is. Everything comes from services/audio-manager; without
/// it nothing is shown as current.
class PhoneDevicesView extends StatefulWidget {
  const PhoneDevicesView({super.key});

  @override
  State<PhoneDevicesView> createState() => _PhoneDevicesViewState();
}

class _PhoneDevicesViewState extends State<PhoneDevicesView> {
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
