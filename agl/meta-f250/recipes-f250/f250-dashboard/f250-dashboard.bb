SUMMARY = "F-250 dashboard (Flutter, 800x480)"
DESCRIPTION = "apps/infotainment as a flutter-auto bundle, reading the \
vehicle gateway's gRPC socket. Started by f250-dashboard.service (f250-system) \
as the compositor's homescreen, in place of the AGL demo homescreen."

require conf/include/f250-source.inc

# The app's dependencies are pure Dart on Linux (grpc, protobuf, fixnum,
# flutter_map and the simulator package in this repo; flutter_map's
# path_provider is pure Dart there), so the plain class does: no native
# plugins.
inherit flutter-app

FLUTTER_APPLICATION_PATH = "apps/infotainment"
PUBSPEC_APPNAME = "f250_infotainment"

# The same defines as `make deploy` (tools/dev/deploy.sh): live data from the
# gateway's socket, the camera view from camera-manager's. The socket paths
# are the units' RuntimeDirectory.
APP_AOT_EXTRA:append = " -DVEHICLE_SOURCE=gateway -DGATEWAY=unix:/run/f250/vehicle.sock -DCAMERAS=unix:/run/f250-camera/camera.sock -DPOWER=unix:/run/f250-power/power.sock -DNAV=unix:/run/f250-nav/nav.sock -DMAP_FILE=/var/lib/f250/maps/map.pmtiles"

# flutter-auto's settings for the bundle: background surface, 800x480,
# fullscreen. Installed as <bundle>/config.toml by the class.
APP_CONFIG = "f250/agl/flutter/config.toml"

# pub fetches the Dart packages in this task (as AGL's homescreen recipe does).
do_compile[network] = "1"

RDEPENDS:${PN} += "flutter-auto agl-flutter-env"
