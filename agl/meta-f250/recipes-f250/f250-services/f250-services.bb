SUMMARY = "F-250 vehicle gateway, recorder, power manager, camera manager, navigation and diagnostics console"
DESCRIPTION = "The Rust services from this repository's Cargo workspace \
(services/vehicle-gateway, services/recorder, services/power-manager, \
services/camera-manager and its camera-ctl, services/navigation, \
tools/obd-console), with the \
gateway's runtime data: the signal registry, the warning rules and the \
simulator scenarios."

require conf/include/f250-source.inc
require f250-services-crates.inc

inherit cargo pkgconfig

# crates/proto runs protoc (tonic-prost-build).
DEPENDS += "protobuf-native"

# The recorder's rusqlite asks for its bundled SQLite, but the cargo class
# exports LIBSQLITE3_SYS_USE_PKG_CONFIG=1 so crates link the image's
# libsqlite3 instead (Yocto policy: no vendored C libraries). The runtime
# dependency on libsqlite3 follows from the binary's shared libraries.
DEPENDS += "sqlite3"

# camera-manager records front and rear with in-process GStreamer
# (gstreamer-rs, ADR-0027 decision 2): its gstreamer feature links
# libgstreamer-1.0 and GLib, found through pkg-config in the sysroot. The
# runtime dependencies follow from the binary's shared libraries; the
# recording plugins are in the image (agl-f250-base.inc).
DEPENDS += "gstreamer1.0 glib-2.0"

# The workspace also holds can-monitor, an offline analysis tool for the Mac;
# build only what the head unit runs. The gateway gets the MX+ over RFCOMM
# (pure Rust, no system library), and camera-manager gets GStreamer, as
# `make deploy` builds them.
CARGO_BUILD_FLAGS:append = " -p vehicle-gateway -p recorder -p obd-console -p power-manager -p camera-manager -p navigation --features vehicle-gateway/rfcomm,camera-manager/gstreamer"

# The same layout as the Stage 1 sideload (ADR-0016), so the units in
# agl/rootfs and `stage1-setup.sh --check` work unchanged.
F250_PREFIX = "/opt/f250"

do_install() {
    install -d ${D}${F250_PREFIX}/bin
    for b in vehicle-gateway recorder obd-console power-manager camera-manager camera-ctl navigation; do
        install -m 0755 ${B}/target/${CARGO_TARGET_SUBDIR}/$b ${D}${F250_PREFIX}/bin/
    done

    # The gateway's runtime data (agl/rootfs/opt/f250/libexec/gateway-start).
    install -d ${D}${F250_PREFIX}/share/data
    cp -R --no-preserve=ownership ${S}/shared/signals ${D}${F250_PREFIX}/share/data/signals
    cp -R --no-preserve=ownership ${S}/simulator/powerstroke/scenarios ${D}${F250_PREFIX}/share/data/scenarios
    install -m 0644 ${S}/apps/infotainment/assets/config/warning_rules.json ${D}${F250_PREFIX}/share/data/
    # navigation's Valhalla config (ADR-0035); Valhalla itself isn't in the image yet.
    install -d ${D}${F250_PREFIX}/share/data/valhalla
    install -m 0644 ${S}/services/navigation/valhalla/valhalla-3.9.1.json ${D}${F250_PREFIX}/share/data/valhalla/
}

FILES:${PN} = "${F250_PREFIX}/bin ${F250_PREFIX}/share/data"
