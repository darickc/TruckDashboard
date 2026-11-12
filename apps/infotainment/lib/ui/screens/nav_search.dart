import 'dart:async';

import 'package:flutter/material.dart';

import '../../model/units.dart';
import '../../nav/route_state.dart';
import '../../nav/search_state.dart';
import '../theme.dart';
import '../widgets/on_screen_keyboard.dart';
import '../widgets/tap_target.dart';

/// Fits under the alert banner too: 12 + 60 + 4 + 4 + the keyboard's 255 px,
/// with 340 px left by the status bar, an alert and the screen's padding.
///
/// Address and place search over the Nav screen (Phase 6.5.3, ADR-0038): a
/// field typed on the on-screen keyboard, results from services/navigation
/// as they come, and on each result Show (on the map) and Route here.
///
/// Honest about what it found: every result says whether it is the address,
/// only the street, only the town, or a named place, and what it didn't
/// match. Searching while the truck moves is allowed (the owner's decision,
/// docs/safety/assumptions.md), with a warning to type only when parked.
class NavSearchPanel extends StatefulWidget {
  const NavSearchPanel({
    super.key,
    required this.source,
    required this.onClose,
    required this.onShow,
    required this.onRoute,
    required this.canRoute,
    required this.moving,
    required this.units,
    this.initialQuery = '',
    this.onQueryChanged,
  });

  final SearchSource source;
  final VoidCallback onClose;
  final ValueChanged<SearchResult> onShow;
  final ValueChanged<SearchResult> onRoute;

  /// Routing is up: Route here is offered.
  final bool canRoute;

  /// The truck is moving (a current speed above the example threshold).
  final bool moving;
  final UnitSystem units;
  final String initialQuery;

  /// The query as typed, so the screen can keep it for next time.
  final ValueChanged<String>? onQueryChanged;

  /// Typing pauses this long before a search goes out.
  static const debounce = Duration(milliseconds: 150);

  /// At most this many characters, as the service reads.
  static const maxChars = 80;

  @override
  State<NavSearchPanel> createState() => _NavSearchPanelState();
}

class _NavSearchPanelState extends State<NavSearchPanel> {
  late String _query = widget.initialQuery;
  bool _keyboard = true;
  SearchAnswer? _answer;
  bool _busy = false;
  int _seq = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (_query.trim().isNotEmpty) _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _set(String q) {
    if (q.length > NavSearchPanel.maxChars) return;
    setState(() => _query = q);
    widget.onQueryChanged?.call(q);
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      _seq++; // drop answers still on their way
      setState(() => _busy = false);
      return;
    }
    _debounce = Timer(NavSearchPanel.debounce, _search);
  }

  Future<void> _search() async {
    final mine = ++_seq;
    final q = _query;
    setState(() => _busy = true);
    final a = await widget.source.search(q);
    if (!mounted || mine != _seq) return; // a newer search is on its way
    setState(() {
      _answer = a;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      key: const ValueKey('nav-search'),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          SizedBox(
            height: kMinTouch,
            child: Row(
              children: [
                Expanded(child: _field(p)),
                const SizedBox(width: kGap),
                TapTarget(
                  key: const ValueKey('nav-search-clear'),
                  label: 'Clear',
                  onTap: () => _set(''),
                  padding: EdgeInsets.zero,
                  child: const Icon(Icons.backspace, size: 28),
                ),
                const SizedBox(width: kGap),
                TapTarget(
                  key: const ValueKey('nav-search-close'),
                  label: 'Close search',
                  onTap: widget.onClose,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.map_outlined, size: 26),
                      SizedBox(width: 6),
                      Text('Map', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(child: _results(p)),
          if (_keyboard) ...[
            const SizedBox(height: 4),
            OnScreenKeyboard(
              onText: (t) => _set(_query + t),
              onBackspace: () => _set(_query.isEmpty ? '' : _query.substring(0, _query.length - 1)),
              onDone: () => setState(() => _keyboard = false),
              doneLabel: 'Results',
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(Palette p) {
    final empty = _query.isEmpty;
    return Semantics(
      textField: true,
      value: _query,
      child: TapTarget(
        key: const ValueKey('nav-search-field'),
        label: 'Search for an address or place',
        selected: _keyboard,
        onTap: () => setState(() => _keyboard = true),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Icon(Icons.search, size: 28, color: p.textDim),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                empty ? 'Address, street, town or place' : _query,
                key: const ValueKey('nav-search-text'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: empty ? p.textDim : p.text),
              ),
            ),
            // The caret: drawn, since the label font has no caret glyph.
            if (_keyboard && !empty)
              Container(width: 2, height: 26, margin: const EdgeInsets.only(left: 1), color: p.accent),
            const Spacer(),
            if (_busy)
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: p.textDim)),
          ],
        ),
      ),
    );
  }

  Widget _results(Palette p) {
    final a = _answer;
    final q = _query.trim();
    final current = a != null && a.query == _query;
    final items = <Widget>[
      if (widget.moving)
        _line(
          'nav-search-moving',
          Icons.warning_amber_rounded,
          'The truck is moving: type only when parked',
          p.advisory,
          p,
        ),
    ];
    if (q.isEmpty) {
      items.add(
        _line('nav-search-hint', Icons.info_outline, 'Type an address, a street, a town or a place name', p.textDim, p),
      );
    } else if (a == null) {
      items.add(_line('nav-search-busy', Icons.hourglass_empty, 'Searching…', p.textDim, p));
    } else if (!a.available) {
      items.add(
        _line(
          'nav-search-unavailable',
          Icons.search_off,
          'Search unavailable: ${a.detail.isEmpty ? 'no answer' : a.detail}',
          p.advisory,
          p,
        ),
      );
    } else if (a.results.isEmpty && current && !_busy) {
      items.add(_line('nav-search-none', Icons.search_off, 'Nothing found for “$q”${_where(a)}', p.textDim, p));
    } else {
      for (final r in a.results) {
        items.add(
          _ResultRow(
            result: r,
            note: matchNote(r, a.query),
            units: widget.units,
            canRoute: widget.canRoute,
            onShow: () => widget.onShow(r),
            onRoute: () => widget.onRoute(r),
            palette: p,
          ),
        );
      }
    }
    if (a != null && a.available && q.isNotEmpty) items.add(_footer(a, p));
    return ListView(key: const ValueKey('nav-search-results'), padding: EdgeInsets.zero, children: items);
  }

  static String _where(SearchAnswer a) => a.regions.isEmpty ? '' : ' in ${a.regions.join(', ')}';

  Widget _footer(SearchAnswer a, Palette p) {
    final ranked = switch (a.rankedFrom) {
      RankedFrom.current => 'Nearest first',
      RankedFrom.lastKnown => 'Nearest to the last known position (${formatDuration(a.positionAgeS)} old)',
      RankedFrom.none => 'Not sorted by distance: no position',
    };
    final data = [
      if (a.regions.isNotEmpty) a.regions.join(', '),
      'OpenStreetMap${a.dataDate.isEmpty ? '' : ' ${a.dataDate}'}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      child: Text(
        [
          '$ranked. Search data: $data. House numbers are sparse outside towns.',
          if (!widget.canRoute) 'Routing is unavailable: Show puts a result on the map.',
        ].join(' '),
        key: const ValueKey('nav-search-footer'),
        style: TextStyle(fontSize: 13, color: p.textDim),
      ),
    );
  }

  Widget _line(String key, IconData icon, String text, Color color, Palette p) => Padding(
    key: ValueKey(key),
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
    child: Row(
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: color == p.textDim ? p.text : color),
          ),
        ),
      ],
    ),
  );
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.result,
    required this.note,
    required this.units,
    required this.canRoute,
    required this.onShow,
    required this.onRoute,
    required this.palette,
  });

  final SearchResult result;
  final String? note;
  final UnitSystem units;
  final bool canRoute;
  final VoidCallback onShow;
  final VoidCallback onRoute;
  final Palette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final r = result;
    final d = r.distanceM;
    final second = [
      matchLabel(r.kind),
      if (r.subtitle.isNotEmpty) r.subtitle,
      if (d != null) '${formatDistance(d, units)} away',
    ].join(' · ');
    return Container(
      key: ValueKey('nav-search-result-${r.title}|${r.subtitle}'),
      constraints: const BoxConstraints(minHeight: kMinTouch + 6),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 4),
          Icon(_icon(r.kind), size: 28, color: note == null ? p.accent : p.advisory),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  r.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text),
                ),
                Text(
                  second,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: p.textDim),
                ),
                if (note != null)
                  Text(
                    note!,
                    key: const ValueKey('nav-search-note'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.advisory),
                  ),
              ],
            ),
          ),
          const SizedBox(width: kGap),
          TapTarget(
            key: const ValueKey('nav-search-show'),
            label: 'Show ${r.title} on the map',
            onTap: onShow,
            padding: EdgeInsets.zero,
            child: const Icon(Icons.place_outlined, size: 28),
          ),
          if (canRoute) ...[
            const SizedBox(width: kGap),
            TapTarget(
              key: const ValueKey('nav-search-route'),
              label: 'Route to ${r.title}',
              onTap: onRoute,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.directions, size: 26),
                  SizedBox(width: 6),
                  Text('Route here', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static IconData _icon(SearchMatch m) => switch (m) {
    SearchMatch.address => Icons.home_outlined,
    SearchMatch.street => Icons.add_road,
    SearchMatch.locality => Icons.location_city,
    SearchMatch.place => Icons.storefront_outlined,
  };
}
