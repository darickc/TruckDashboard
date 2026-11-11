import 'dart:async';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme.dart';
import 'tap_target.dart';

/// How long the result of a save stays on the button.
const kSaveClipResultFor = Duration(seconds: 6);

/// "Save clip" (ADR-0027 decision 8): asks camera-manager to protect the
/// segment being written and the minutes around it. The button itself says
/// what happened for a few seconds: saved, or not saved and why (camera-
/// manager refuses when nothing records or the saved clips are full). With
/// the simulated source nothing is saved, and it says SIMULATED.
class SaveClipButton extends StatefulWidget {
  const SaveClipButton({super.key, required this.keyPrefix, this.compact = false});

  /// Keys: `<prefix>` on the button, `<prefix>-result` on the result line.
  final String keyPrefix;

  /// Camera mode's column: smaller text, one detail line.
  final bool compact;

  @override
  State<SaveClipButton> createState() => _SaveClipButtonState();
}

class _SaveClipButtonState extends State<SaveClipButton> {
  bool _saving = false;
  (bool ok, String title, String detail)? _result;
  Timer? _clear;

  @override
  void dispose() {
    _clear?.cancel();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final cameras = AppScope.of(context).cameras;
    setState(() {
      _saving = true;
      _result = null;
    });
    (bool, String, String) result;
    try {
      final r = await cameras.saveClip();
      final simulated = cameras.status.value.simulated;
      final detail = r.detail.isNotEmpty
          ? r.detail
          : '${r.segmentsProtected} segments saved, ${r.segmentsToCome} to come';
      result = (r.saved, r.saved ? (simulated ? 'SIMULATED' : 'Saved') : 'Not saved', detail);
    } catch (_) {
      result = (false, 'Not saved', "camera-manager didn't answer");
    }
    if (!mounted) return;
    _clear?.cancel();
    _clear = Timer(kSaveClipResultFor, () {
      if (mounted) setState(() => _result = null);
    });
    setState(() {
      _saving = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final r = _result;
    final simulated = AppScope.of(context).cameras.status.value.simulated;
    final color = r == null
        ? p.text
        : !r.$1
            ? p.advisory
            : simulated
                ? p.simulated
                : p.ok;
    final title = _saving ? 'Saving…' : (r?.$2 ?? 'Save clip');
    return TapTarget(
      key: ValueKey(widget.keyPrefix),
      label: r == null ? 'Save clip' : '${r.$2}: ${r.$3}',
      padding: EdgeInsets.symmetric(horizontal: widget.compact ? 10 : 12, vertical: 4),
      onTap: _save,
      child: Row(mainAxisSize: widget.compact ? MainAxisSize.max : MainAxisSize.min, children: [
        Icon(r == null ? Icons.bookmark_add_outlined : (r.$1 ? Icons.bookmark_added : Icons.error_outline),
            size: widget.compact ? 30 : 28, color: color),
        const SizedBox(width: 10),
        Flexible(
          fit: widget.compact ? FlexFit.tight : FlexFit.loose,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: widget.compact ? 20 : 18,
                        fontWeight: FontWeight.w700,
                        color: color)),
                if (r != null)
                  Text(r.$3,
                      key: ValueKey('${widget.keyPrefix}-result'),
                      maxLines: widget.compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: widget.compact ? 12 : 14, color: p.text)),
              ]),
        ),
      ]),
    );
  }
}
