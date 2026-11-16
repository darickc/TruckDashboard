/// Where the navigation data comes from and under which licence, for
/// Diagnostics → Licences (docs/setup/map-data.md). The OSMF attribution
/// guideline asks that the ODbL and openstreetmap.org/copyright can be found
/// on a device whose credit can't be a link: this is that place.
library;

/// The OpenStreetMap credit shown on the map when the map file has none of
/// its own, and with a route or destination when there is no map file.
const kOsmCredit = '© OpenStreetMap contributors';

/// Where OpenStreetMap's sources and the ODbL are explained.
const kOsmCopyrightUrl = 'openstreetmap.org/copyright';

class DataLicence {
  const DataLicence({required this.key, required this.title, required this.text});

  final String key;
  final String title;
  final String text;
}

/// Every source of the data the Nav screen shows, as in map-data.md's table.
const dataLicences = [
  DataLicence(
    key: 'osm',
    title: 'OpenStreetMap',
    text:
        'Map, routing and search data $kOsmCredit, available under the Open Database '
        'License (ODbL) 1.0. Sources and licence: $kOsmCopyrightUrl',
  ),
  DataLicence(
    key: 'natural-earth',
    title: 'Natural Earth',
    text: 'The map at low zooms (in Protomaps builds). Public domain.',
  ),
  DataLicence(
    key: 'timezones',
    title: 'Time zones',
    text: 'In the routing data: timezone-boundary-builder, from OpenStreetMap, ODbL 1.0.',
  ),
  DataLicence(
    key: 'census',
    title: 'U.S. Census Bureau',
    text:
        'ESTIMATED house numbers in search: TIGER/Line address ranges. Source: '
        'U.S. Census Bureau.',
  ),
  DataLicence(
    key: 'style',
    title: 'Map style, icons and fonts',
    text:
        'Protomaps basemaps (BSD-3-Clause; the design CC0), icons derived from '
        'Tangrams (MIT), Noto Sans (SIL Open Font License 1.1).',
  ),
];
