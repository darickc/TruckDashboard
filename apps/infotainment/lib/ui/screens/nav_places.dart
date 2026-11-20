import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../model/units.dart';
import '../../nav/places_state.dart';
import '../../nav/route_state.dart' show formatDistance;
import '../theme.dart';
import '../widgets/on_screen_keyboard.dart';
import '../widgets/tap_target.dart';

/// Saved places over the Nav screen (Phase 6.5.2, ADR-0040): Home,
/// favourites and the recent destinations, each with Route here (one tap)
/// and Edit (rename or delete: two taps). services/navigation keeps them;
/// the panel asks it again each time it opens, since every route adds a
/// recent one.
///
/// Each place shows its straight-line distance and direction from the truck
/// while the position is current ([here]); without one, a dash, never a
/// distance from an old position (CLAUDE.md rule 4).
class NavPlacesPanel extends StatefulWidget {
  const NavPlacesPanel({
    super.key,
    required this.source,
    required this.canRoute,
    required this.onRoute,
    required this.onEdit,
    required this.onSearch,
    required this.onClose,
    this.here,
    this.units = UnitSystem.imperial,
  });

  final PlacesSource source;

  /// The truck's position while it is current; null without a current fix.
  final LatLng? here;
  final UnitSystem units;

  /// Routing is up: Route here is offered.
  final bool canRoute;
  final ValueChanged<Place> onRoute;
  final ValueChanged<Place> onEdit;
  final VoidCallback onSearch;
  final VoidCallback onClose;

  @override
  State<NavPlacesPanel> createState() => _NavPlacesPanelState();
}

class _NavPlacesPanelState extends State<NavPlacesPanel> {
  @override
  void initState() {
    super.initState();
    widget.source.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      key: const ValueKey('nav-places'),
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
                const SizedBox(width: 6),
                Icon(Icons.star, size: 28, color: p.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Saved places',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.text),
                      ),
                      Text(
                        widget.here == null
                            ? 'No current position: no distances'
                            : 'Distances in a straight line from the truck',
                        key: const ValueKey('nav-places-distances'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: p.textDim),
                      ),
                    ],
                  ),
                ),
                _labelled('nav-places-search', 'Search', Icons.search, widget.onSearch),
                const SizedBox(width: kGap),
                _labelled('nav-places-close', 'Map', Icons.map_outlined, widget.onClose),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: widget.source.state,
              builder: (context, view, _) => _list(view, p),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(PlacesView v, Palette p) {
    final items = <Widget>[];
    if (v.link != PlacesLink.connected) {
      items.add(
        v.link == PlacesLink.connecting
            ? placesLine('nav-places-loading', Icons.hourglass_empty, 'Loading saved places…', p.textDim, p)
            : placesLine(
                'nav-places-unavailable',
                Icons.cloud_off,
                'Saved places unavailable: ${v.detail.isEmpty ? 'no answer' : v.detail}',
                p.advisory,
                p,
              ),
      );
      return ListView(key: const ValueKey('nav-places-list'), padding: EdgeInsets.zero, children: items);
    }
    // A problem goes first, where it can't be missed.
    if (v.problem.isNotEmpty) {
      items.add(placesLine('nav-places-problem', Icons.warning_amber_rounded, v.problem, p.advisory, p));
    }
    final home = v.home;
    if (home != null) {
      items.add(_row(home, p, home: true));
    } else {
      items.add(
        placesLine(
          'nav-places-no-home',
          Icons.home_outlined,
          'No Home yet: choose a point (long-press the map, or Search), then Save',
          p.textDim,
          p,
        ),
      );
    }
    items.add(_heading('FAVOURITES · ${v.favourites.length} OF ${v.maxFavourites}', p));
    if (v.favourites.isEmpty) {
      items.add(placesLine('nav-places-no-favourites', Icons.star_border, 'None yet', p.textDim, p));
    }
    items.addAll(v.favourites.map((f) => _row(f, p)));
    items.add(_heading(v.recents.isEmpty ? 'RECENT' : 'RECENT · ${v.recents.length}', p));
    if (v.recents.isEmpty) {
      items.add(placesLine('nav-places-no-recents', Icons.history, 'Destinations you route to appear here', p.textDim, p));
    }
    items.addAll(v.recents.map((r) => _row(r, p)));
    items.add(
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: Text(
          [
            'Kept on ${v.location.isEmpty ? 'the head unit' : v.location}.',
            if (!v.writable) 'Read-only: nothing can be saved or changed.',
            if (!widget.canRoute) 'Routing is unavailable.',
          ].join(' '),
          key: const ValueKey('nav-places-footer'),
          style: TextStyle(fontSize: 13, color: p.textDim),
        ),
      ),
    );
    return ListView(key: const ValueKey('nav-places-list'), padding: EdgeInsets.zero, children: items);
  }

  Widget _heading(String text, Palette p) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 10, 4, 2),
    child: Text(
      text,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: p.textDim),
    ),
  );

  Widget _row(Place place, Palette p, {bool home = false}) {
    final (title, detail) = placeLines(place);
    final here = widget.here;
    final (dist, dir) = here == null ? ('—', '') : placeDistance(here, place.location, widget.units);
    return Container(
      key: ValueKey('nav-place-${place.id}'),
      constraints: const BoxConstraints(minHeight: kMinTouch + 6),
      padding: const EdgeInsets.symmetric(vertical: 3),
      decoration: home
          ? BoxDecoration(
              color: p.accent.withValues(alpha: 0.10),
              border: Border.all(color: p.accent.withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(10),
            )
          : BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
      child: Row(
        children: [
          const SizedBox(width: 6),
          Icon(placeIcon(place), size: 28, color: p.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: p.textDim),
                  ),
              ],
            ),
          ),
          const SizedBox(width: kGap),
          SizedBox(
            width: 84,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  dist,
                  key: const ValueKey('nav-place-distance'),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: here == null ? p.textDim : p.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (dir.isNotEmpty)
                  Text(
                    dir,
                    key: const ValueKey('nav-place-direction'),
                    style: TextStyle(fontSize: 13, color: p.textDim),
                  ),
              ],
            ),
          ),
          const SizedBox(width: kGap),
          TapTarget(
            key: const ValueKey('nav-place-edit'),
            label: 'Edit $title',
            onTap: () => widget.onEdit(place),
            padding: EdgeInsets.zero,
            child: const Icon(Icons.edit_outlined, size: 26),
          ),
          if (widget.canRoute) ...[
            const SizedBox(width: kGap),
            SizedBox(
              width: 72,
              child: TapTarget(
                key: const ValueKey('nav-place-route'),
                label: 'Route here: $title',
                onTap: () => widget.onRoute(place),
                padding: EdgeInsets.zero,
                fill: p.accent,
                child: Icon(Icons.directions, size: 30, color: TapTarget.onFill(p.accent)),
              ),
            ),
          ],
          if (home) const SizedBox(width: 3),
        ],
      ),
    );
  }
}

/// The row's two lines: an unnamed point is a dropped pin, with where it is
/// underneath.
(String, String) placeLines(Place place) {
  if (place.name.isNotEmpty) return (place.name, place.detail);
  final at = '${place.location.latitude.toStringAsFixed(4)}, ${place.location.longitude.toStringAsFixed(4)}';
  return ('Dropped pin', place.detail.isEmpty ? at : '${place.detail} · $at');
}

const _distance = Distance();
const _compass = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

/// Straight-line distance and compass direction from [from] to [to]: whole
/// miles or km from 10 up, else as the guidance banner gives it; "here"
/// within 50 m, where a direction means nothing.
(String, String) placeDistance(LatLng from, LatLng to, UnitSystem units) {
  final m = _distance.as(LengthUnit.Meter, from, to);
  final unit = units == UnitSystem.imperial ? 1609.344 : 1000.0;
  final text = m / unit >= 10
      ? '${(m / unit).round()} ${units == UnitSystem.imperial ? 'mi' : 'km'}'
      : formatDistance(m, units);
  if (m < 50) return (text, 'here');
  final bearing = (_distance.bearing(from, to) + 360) % 360;
  return (text, _compass[(bearing / 45).round() % 8]);
}

IconData placeIcon(Place place) => switch (place.kind) {
  PlaceKind.home => Icons.home,
  PlaceKind.favourite => Icons.star,
  PlaceKind.recent => place.name.isEmpty ? Icons.place_outlined : Icons.history,
};

Widget _labelled(String key, String label, IconData icon, VoidCallback onTap, {Color? color}) => TapTarget(
  key: ValueKey(key),
  label: label,
  onTap: onTap,
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 26, color: color),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: color)),
    ],
  ),
);

Widget placesLine(String key, IconData icon, String text, Color color, Palette p) => Padding(
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

/// A place being saved (from a map pin, a search result or the route's
/// destination) or edited (one already saved).
@immutable
class PlaceDraft {
  const PlaceDraft({required this.location, this.name = '', this.detail = '', this.existing});

  final LatLng location;
  final String name;
  final String detail;

  /// The saved place being edited, or null for a new one.
  final Place? existing;
}

/// Names a place and saves it as a favourite or as Home, or renames or
/// deletes a saved one. The name is typed on the on-screen keyboard; typing
/// while moving is allowed, with the same warning as search (the owner's
/// decision, docs/safety/assumptions.md).
///
/// Fits under the alert banner: the actions share the field's row, so it is
/// 12 + 60 + 4 + 4 + the keyboard's 255 px, like the search panel. A failure
/// hides the keyboard so the reason shows.
class NavPlaceEditor extends StatefulWidget {
  const NavPlaceEditor({
    super.key,
    required this.draft,
    required this.source,
    required this.moving,
    required this.onClose,
  });

  final PlaceDraft draft;
  final PlacesSource source;

  /// The truck is moving (a current speed above the example threshold).
  final bool moving;

  /// Done or cancelled.
  final VoidCallback onClose;

  @override
  State<NavPlaceEditor> createState() => _NavPlaceEditorState();
}

class _NavPlaceEditorState extends State<NavPlaceEditor> {
  late String _name = widget.draft.name;
  bool _keyboard = true;
  bool _busy = false;
  bool _needName = false;
  String? _error;

  Place? get _existing => widget.draft.existing;

  void _set(String s) {
    final max = widget.source.state.value.maxNameChars;
    if (s.length > max) return;
    setState(() {
      _name = s;
      _needName = false;
    });
  }

  Future<void> _run(Future<String?> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final why = await action();
    if (!mounted) return;
    if (why == null) {
      widget.onClose();
      return;
    }
    setState(() {
      _busy = false;
      _error = why;
      _keyboard = false; // so the reason shows, under an alert too
    });
  }

  void _saveFavourite() {
    final name = _name.trim();
    if (name.isEmpty) {
      setState(() => _needName = true);
      return;
    }
    final e = _existing;
    final d = widget.draft;
    _run(
      () => e != null && e.kind != PlaceKind.recent
          ? widget.source.rename(e.id, name)
          : widget.source.save(PlaceKind.favourite, name, d.location, detail: d.detail),
    );
  }

  void _saveHome() {
    final d = widget.draft;
    // Home keeps where it is; the address goes on its second line.
    final detail = d.detail.isNotEmpty ? d.detail : _name.trim();
    _run(() => widget.source.save(PlaceKind.home, 'Home', d.location, detail: detail));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final e = _existing;
    final rename = e != null && e.kind != PlaceKind.recent;
    final actions = <Widget>[
      _labelled('nav-place-save', rename ? 'Save' : 'Favourite', rename ? Icons.check : Icons.star, _saveFavourite),
      if (!rename) ...[const SizedBox(width: kGap), _labelled('nav-place-home', 'Home', Icons.home, _saveHome)],
      if (e != null) ...[
        const SizedBox(width: kGap),
        TapTarget(
          key: const ValueKey('nav-place-delete'),
          label: 'Delete ${e.title}',
          onTap: () => _run(() => widget.source.delete(e.id)),
          padding: EdgeInsets.zero,
          child: Icon(Icons.delete_outline, size: 28, color: p.advisory),
        ),
      ],
      const SizedBox(width: kGap),
      TapTarget(
        key: const ValueKey('nav-place-cancel'),
        label: 'Cancel',
        onTap: widget.onClose,
        padding: EdgeInsets.zero,
        child: const Icon(Icons.close, size: 28),
      ),
    ];
    final what = switch (e?.kind) {
      null => 'Save this place as a favourite (it needs a name) or as Home.',
      PlaceKind.recent => 'A recent destination: save it as a favourite or as Home, or delete it.',
      PlaceKind.home => 'Home: rename or delete it.',
      PlaceKind.favourite => 'A favourite: rename or delete it.',
    };
    final d = widget.draft;
    return Container(
      key: const ValueKey('nav-place-editor'),
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
            child: Row(children: [Expanded(child: _field(p)), const SizedBox(width: kGap), ...actions]),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                if (_error != null)
                  placesLine('nav-place-error', Icons.error_outline, 'Not saved: $_error', p.advisory, p),
                if (widget.moving)
                  placesLine(
                    'nav-place-moving',
                    Icons.warning_amber_rounded,
                    'The truck is moving: type only when parked',
                    p.advisory,
                    p,
                  ),
                placesLine('nav-place-what', Icons.info_outline, what, p.textDim, p),
                Padding(
                  padding: const EdgeInsets.fromLTRB(34, 0, 4, 4),
                  child: Text(
                    [
                      if (d.detail.isNotEmpty) d.detail,
                      '${d.location.latitude.toStringAsFixed(5)}, ${d.location.longitude.toStringAsFixed(5)}',
                    ].join(' · '),
                    key: const ValueKey('nav-place-where'),
                    style: TextStyle(fontSize: 14, color: p.textDim),
                  ),
                ),
              ],
            ),
          ),
          if (_keyboard) ...[
            const SizedBox(height: 4),
            OnScreenKeyboard(
              onText: (t) => _set(_name + t),
              onBackspace: () => _set(_name.isEmpty ? '' : _name.substring(0, _name.length - 1)),
              onDone: () => setState(() => _keyboard = false),
              doneLabel: 'Done',
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(Palette p) {
    final empty = _name.isEmpty;
    final placeholder = _needName ? 'Type a name first' : 'Name';
    return Semantics(
      textField: true,
      value: _name,
      child: TapTarget(
        key: const ValueKey('nav-place-field'),
        label: 'The place\'s name',
        selected: _keyboard,
        onTap: () => setState(() => _keyboard = true),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Icon(Icons.edit, size: 24, color: p.textDim),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                empty ? placeholder : _name,
                key: const ValueKey('nav-place-name'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: empty ? (_needName ? p.advisory : p.textDim) : p.text,
                ),
              ),
            ),
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
}
