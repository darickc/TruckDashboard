import 'package:flutter/material.dart';

import '../../export/export_state.dart';
import '../../export/recording_selection.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/badges.dart';
import '../widgets/panel.dart';
import '../widgets/tap_target.dart';

/// Copies dashcam recordings to a USB stick plugged into the head unit
/// (ADR-0037), opened from Cameras. On the left the recordings by run,
/// camera and time (saved clips marked), filtered and chosen; on the right
/// the stick, the size against its free space, the copy's progress, and
/// when it is safe to pull the stick out. services/usb-export does the
/// copying; this screen only asks it and shows what it says. Copy only:
/// nothing is deleted from the truck.
class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  final _selection = RecordingSelection();
  RecordingList? _list;
  String? _listError;
  bool _loading = false;
  String? _device;

  /// Why the last tap didn't start a copy, or what went wrong asking.
  String? _message;
  int _lastCopyId = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_list == null && !_loading) _load();
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final source = AppScope.of(context).exports;
    setState(() {
      _loading = true;
      _listError = null;
    });
    try {
      final list = await source.list();
      if (!mounted) return;
      _selection.setRecordings(list.recordings);
      setState(() {
        _list = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _listError = 'The recordings couldn\'t be listed: $e';
        _loading = false;
      });
    }
  }

  /// The stick recordings go to: the one chosen, else the first that can
  /// take them, else the first plugged in.
  UsbStick? _stick(ExportStatus s) {
    if (s.sticks.isEmpty) return null;
    for (final k in s.sticks) {
      if (k.device == _device) return k;
    }
    return s.sticks.firstWhere((k) => k.role == StickRole.export, orElse: () => s.sticks.first);
  }

  Future<void> _copy(ExportStatus status, UsbStick? stick) async {
    final why = _whyNot(status, stick);
    if (why != null) {
      setState(() => _message = why);
      return;
    }
    setState(() => _message = null);
    try {
      final r = await AppScope.of(context).exports.startCopy(stick!.device, _selection.chosen);
      if (!mounted) return;
      setState(() => _message = r.started ? null : r.detail);
    } catch (e) {
      if (mounted) setState(() => _message = 'The copy couldn\'t be started: $e');
    }
  }

  Future<void> _cancel() async {
    try {
      await AppScope.of(context).exports.cancel();
    } catch (e) {
      if (mounted) setState(() => _message = 'The copy couldn\'t be cancelled: $e');
    }
  }

  /// Why Copy can't start now, or null.
  String? _whyNot(ExportStatus status, UsbStick? stick) {
    if (status.link != ExportLink.up) return 'usb-export isn\'t reachable: nothing can be copied.';
    if (stick == null) return 'Plug a USB stick into the head unit first.';
    if (stick.role == StickRole.checking) return 'The stick is still being checked.';
    if (stick.role != StickRole.export) return stick.detail;
    if (stick.readOnly) return stick.detail.isEmpty ? 'The stick is read-only.' : stick.detail;
    return switch (_selection.fitOn(stick)) {
      Fit.nothingChosen => 'Choose the recordings to copy first.',
      Fit.tooBig => 'The chosen recordings don\'t fit on the stick: choose fewer.',
      Fit.fileTooBig =>
        'A recording is over this stick\'s 4 GB file limit (FAT): use an exFAT stick.',
      Fit.noStick => 'Plug a USB stick into the head unit first.',
      Fit.fits => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ValueListenableBuilder(
      valueListenable: s.exports.status,
      builder: (context, status, _) {
        final copy = status.copy;
        // A new copy's first state clears the last refusal.
        if (copy != null && copy.id != _lastCopyId && copy.phase != CopyPhase.idle) {
          _lastCopyId = copy.id;
          _message = null;
        }
        return ListenableBuilder(
          listenable: _selection,
          builder: (context, _) {
            final p = Palette.of(context);
            return Panel(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _left(p, status)),
                  VerticalDivider(width: 20, color: p.border),
                  SizedBox(width: 290, child: _right(p, status)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ---- the list ------------------------------------------------------------

  Widget _left(Palette p, ExportStatus status) {
    final busy = status.copy?.running ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: kMinTouch,
          child: Row(
            children: [
              for (final (f, label) in const [
                (RecordingFilter.all, 'All'),
                (RecordingFilter.front, 'Front'),
                (RecordingFilter.rear, 'Rear'),
                (RecordingFilter.saved, 'Saved'),
              ]) ...[
                TapTarget(
                  key: ValueKey('rec-filter-${f.name}'),
                  label: 'Show ${label.toLowerCase()} recordings',
                  selected: _selection.filter == f,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  onTap: () => _selection.filter = f,
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              const Spacer(),
              TapTarget(
                key: const ValueKey('rec-refresh'),
                label: 'Read the recordings again',
                padding: EdgeInsets.zero,
                onTap: busy ? () {} : _load,
                child: Icon(Icons.refresh_rounded, size: 28, color: busy ? p.textDim : p.text),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(child: _listBody(p)),
      ],
    );
  }

  Widget _listBody(Palette p) {
    Widget note(String key, String text, Color color) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        key: ValueKey(key),
        style: TextStyle(fontSize: 15, color: color),
      ),
    );
    final list = _list;
    if (_listError != null) return note('rec-list-error', _listError!, p.advisory);
    if (list == null) return note('rec-loading', 'Reading the recordings…', p.textDim);
    if (list.recordings.isEmpty) {
      return note(
        'rec-empty',
        list.problem.isNotEmpty ? list.problem : 'There are no recordings on the data drive.',
        list.driveMounted ? p.textDim : p.advisory,
      );
    }
    final shown = _selection.shown;
    if (shown.isEmpty) return note('rec-none-shown', 'None of these recordings.', p.textDim);
    // Built lazily: a day of both cameras is thousands of rows.
    final entries = <(String, RecordingFile?)>[
      if (list.problem.isNotEmpty) ('problem', null),
    ];
    int? run;
    for (final r in shown) {
      if (r.boot != run) {
        run = r.boot;
        entries.add(('run', r));
      }
      entries.add(('row', r));
    }
    return ListView.builder(
      key: const ValueKey('rec-list'),
      itemCount: entries.length,
      itemBuilder: (context, i) => switch (entries[i]) {
        ('run', final r?) => _runHeader(p, r, shown),
        ('row', final r?) =>
          Padding(padding: const EdgeInsets.only(bottom: 4), child: _row(p, r)),
        _ => note('rec-problem', list.problem, p.advisory),
      },
    );
  }

  Widget _runHeader(Palette p, RecordingFile first, List<RecordingFile> shown) {
    final timed = shown.where((r) => r.boot == first.boot && r.wallTime != null);
    final when = timed.isEmpty
        ? 'time unknown (clock not synchronized)'
        : formatDay(timed.first.wallTime!);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 0, 4),
      child: Text(
        'Run ${first.boot} · $when',
        key: ValueKey('rec-run-${first.boot}'),
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.textDim),
      ),
    );
  }

  Widget _row(Palette p, RecordingFile r) {
    final chosen = _selection.isChosen(r);
    final anchor = _selection.anchor == r.key;
    final dim = r.beingWritten;
    final color = dim ? p.textDim : p.text;
    return TapTarget(
      key: ValueKey('rec-${r.key}'),
      label:
          '${r.camera} recording ${r.wallTime == null ? 'number ${r.seq}' : formatTime(r.wallTime!)}'
          '${chosen ? ', chosen' : ''}',
      selected: chosen,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      onTap: () => _selection.tap(r),
      child: Row(
        children: [
          Icon(
            dim
                ? Icons.fiber_manual_record
                : chosen
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            size: 26,
            color: dim ? p.critical : (chosen || anchor ? p.accent : p.textDim),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            child: Text(
              r.camera == 'front' ? 'Front' : (r.camera == 'rear' ? 'Rear' : r.camera),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color),
            ),
          ),
          Expanded(
            child: Text(
              r.wallTime == null ? '#${r.seq} · no time' : formatTime(r.wallTime!),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16, color: color),
            ),
          ),
          if (r.protected) ...[
            Pill('SAVED', key: ValueKey('rec-saved-${r.key}'), color: p.accent),
            const SizedBox(width: 6),
          ],
          if (dim) ...[Pill('RECORDING', color: p.textDim), const SizedBox(width: 6)],
          Text(formatSize(r.bytes), style: TextStyle(fontSize: 14, color: p.textDim)),
        ],
      ),
    );
  }

  // ---- the stick and the copy ---------------------------------------------

  Widget _right(Palette p, ExportStatus status) {
    final stick = _stick(status);
    final copy = status.copy;
    final running = copy?.running ?? false;
    final why = _whyNot(status, stick);
    Widget text(String key, String t, Color c, {double size = 15, FontWeight? weight}) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        t,
        key: ValueKey(key),
        style: TextStyle(fontSize: size, color: c, fontWeight: weight),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                'To USB',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.text),
              ),
            ),
            if (status.simulated) ...[
              const SizedBox(width: 8),
              Pill('SIMULATED', key: const ValueKey('rec-simulated'), color: p.simulated),
            ],
            const Spacer(),
            if (status.sticks.length > 1)
              TapTarget(
                key: const ValueKey('rec-next-stick'),
                label: 'Use the next stick',
                padding: const EdgeInsets.symmetric(horizontal: 6),
                onTap: running ? () {} : () => _nextStick(status, stick),
                child: Text(
                  'Stick ${status.sticks.indexOf(stick!) + 1}/${status.sticks.length}',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ..._stickLines(p, status, stick, text),
                ..._choiceLines(p, stick, text),
                if (copy != null) ..._copyLines(p, status, copy, text),
                if (_message != null) text('rec-message', _message!, p.advisory),
              ],
            ),
          ),
        ),
        if (!running) ...[
          SizedBox(
            height: kMinTouch,
            child: Row(
              children: [
                Expanded(
                  child: _small(
                    p,
                    'rec-range',
                    _selection.rangeMode ? 'Range: tap end' : 'Range',
                    'Choose a range: tap the first and last recording',
                    _selection.toggleRangeMode,
                    selected: _selection.rangeMode,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _small(
                    p,
                    'rec-all',
                    'All shown',
                    'Choose every recording shown',
                    _selection.chooseAllShown,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(child: _small(p, 'rec-clear', 'Clear', 'Choose none', _selection.clear)),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
        SizedBox(
          height: kMinTouch,
          child: running
              ? TapTarget(
                  key: const ValueKey('rec-cancel'),
                  label: 'Cancel the copy',
                  onTap: _cancel,
                  child: Text(
                    'Cancel copy',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.advisory),
                  ),
                )
              : TapTarget(
                  key: const ValueKey('rec-copy'),
                  label: why == null ? 'Copy the chosen recordings to the stick' : 'Copy: $why',
                  selected: why == null,
                  onTap: () => _copy(status, stick),
                  child: Text(
                    _selection.chosen.isEmpty
                        ? 'Copy to stick'
                        : 'Copy ${_selection.chosen.length} to stick',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: why == null ? p.text : p.textDim,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  void _nextStick(ExportStatus status, UsbStick? current) {
    final i = current == null ? -1 : status.sticks.indexOf(current);
    setState(() => _device = status.sticks[(i + 1) % status.sticks.length].device);
  }

  Widget _small(
    Palette p,
    String key,
    String label,
    String semantics,
    VoidCallback onTap, {
    bool selected = false,
  }) => TapTarget(
    key: ValueKey(key),
    label: semantics,
    selected: selected,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    onTap: onTap,
    child: Text(
      label,
      textAlign: TextAlign.center,
      maxLines: 2,
      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text),
    ),
  );

  List<Widget> _stickLines(
    Palette p,
    ExportStatus status,
    UsbStick? stick,
    Widget Function(String, String, Color, {double size, FontWeight? weight}) text,
  ) {
    if (status.link != ExportLink.up) {
      return [
        text(
          'rec-stick',
          status.link == ExportLink.connecting
              ? 'Connecting to usb-export…'
              : 'usb-export isn\'t reachable${status.detail == null ? '' : ': ${status.detail}'}. '
                    'Recordings can\'t be copied until it is.',
          status.link == ExportLink.connecting ? p.textDim : p.advisory,
        ),
      ];
    }
    if (stick == null) {
      return [text('rec-stick', 'No USB stick. Plug one (exFAT) into the head unit.', p.textDim)];
    }
    final name = '${stick.name}${stick.filesystem.isEmpty ? '' : ' · ${fsName(stick.filesystem)}'}';
    return switch (stick.role) {
      StickRole.checking => [text('rec-stick', '$name: checking it…', p.textDim)],
      StickRole.map || StickRole.unusable => [
        text('rec-stick', name, p.text, weight: FontWeight.w700),
        text('rec-stick-detail', stick.detail, p.advisory),
      ],
      StickRole.export => [
        text('rec-stick', name, p.text, weight: FontWeight.w700),
        text(
          'rec-stick-free',
          '${formatSize(stick.freeBytes)} free of ${formatSize(stick.totalBytes)}',
          p.textDim,
        ),
        if (stick.readOnly)
          text('rec-stick-detail', stick.detail.isEmpty ? 'Read-only.' : stick.detail, p.advisory),
      ],
    };
  }

  List<Widget> _choiceLines(
    Palette p,
    UsbStick? stick,
    Widget Function(String, String, Color, {double size, FontWeight? weight}) text,
  ) {
    final n = _selection.chosen.length;
    if (n == 0) {
      return [
        text(
          'rec-chosen',
          _selection.rangeMode ? 'Tap the first recording of the range.' : 'Nothing chosen.',
          p.textDim,
        ),
      ];
    }
    final fit = _selection.fitOn(stick);
    return [
      text(
        'rec-chosen',
        '$n chosen · ${formatSize(_selection.chosenBytes)}',
        p.text,
        weight: FontWeight.w700,
      ),
      if (fit == Fit.tooBig)
        text('rec-fit', 'Too big for the stick: ${formatSize(stick!.freeBytes)} free.', p.advisory),
      if (fit == Fit.fileTooBig)
        text(
          'rec-fit',
          'A recording is over FAT\'s 4 GB file limit: use an exFAT stick.',
          p.advisory,
        ),
      if (fit == Fit.fits) text('rec-fit', 'Fits on the stick.', p.ok),
    ];
  }

  List<Widget> _copyLines(
    Palette p,
    ExportStatus status,
    CopyStatus c,
    Widget Function(String, String, Color, {double size, FontWeight? weight}) text,
  ) {
    if (c.phase == CopyPhase.idle) return const [];
    final plugged = status.sticks.any((k) => k.device == c.device);
    if (c.running) {
      return [
        const SizedBox(height: 6),
        LinearProgressIndicator(
          key: const ValueKey('rec-progress'),
          value: c.phase == CopyPhase.copying ? c.fraction : null,
          minHeight: 10,
          color: p.accent,
          backgroundColor: p.surfaceHigh,
        ),
        const SizedBox(height: 6),
        text(
          'rec-progress-text',
          '${c.filesDone} of ${c.filesTotal} files · ${formatSize(c.bytesDone)} of ${formatSize(c.bytesTotal)}',
          p.text,
        ),
        if (c.current.isNotEmpty) text('rec-current', c.current, p.textDim, size: 13),
        text(
          'rec-copy-detail',
          c.detail.isEmpty ? 'Leave the stick in.' : c.detail,
          p.advisory,
          weight: FontWeight.w700,
        ),
      ];
    }
    return [
      const SizedBox(height: 6),
      text('rec-copy-detail', c.detail, c.phase == CopyPhase.done ? p.ok : p.advisory),
      if (c.safeToUnplug)
        text(
          'rec-safe',
          plugged ? 'Safe to unplug the stick.' : 'The stick has been removed.',
          p.ok,
          weight: FontWeight.w800,
          size: 17,
        )
      else
        text(
          'rec-safe',
          'Don\'t unplug the stick yet.',
          p.critical,
          weight: FontWeight.w800,
          size: 17,
        ),
    ];
  }
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _two(int n) => n.toString().padLeft(2, '0');

/// `Thu 12 Nov`, in the head unit's time zone.
String formatDay(DateTime t) {
  final l = t.toLocal();
  return '${_days[l.weekday - 1]} ${l.day} ${_months[l.month - 1]}';
}

/// `04:52:15`, in the head unit's time zone.
String formatTime(DateTime t) {
  final l = t.toLocal();
  return '${_two(l.hour)}:${_two(l.minute)}:${_two(l.second)}';
}

String fsName(String fs) => switch (fs) {
  'exfat' => 'exFAT',
  'vfat' => 'FAT',
  'ntfs' => 'NTFS',
  _ => fs,
};
