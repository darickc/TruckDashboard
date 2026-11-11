SUMMARY = "F-250 vehicle gateway, recorder, power manager, camera manager and diagnostics console"
DESCRIPTION = "The Rust services from this repository's Cargo workspace \
(services/vehicle-gateway, services/recorder, services/power-manager, \
services/camera-manager and its camera-ctl, tools/obd-console), with the \
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

# The workspace also holds can-monitor, an offline analysis tool for the Mac;
# build only what the head unit runs. The gateway gets the MX+ over RFCOMM
# (pure Rust, no system library), as `make deploy` builds it.
# camera-manager is built without its gstreamer feature here, so the image's
# camera-manager shows cameras through gst-launch-1.0 and says it can't
# record (ADR-0027 "As built"). TODO (Phase 6.6): add camera-manager/gstreamer
# with DEPENDS += "gstreamer1.0", and the matroska and multifile plugins to
# the image, by the package names in the build's package list; then build
# and check the image. `make deploy` already builds it with GStreamer.
CARGO_BUILD_FLAGS:append = " -p vehicle-gateway -p recorder -p obd-console -p power-manager -p camera-manager --features vehicle-gateway/rfcomm"

# The same layout as the Stage 1 sideload (ADR-0016), so the units in
# agl/rootfs and `stage1-setup.sh --check` work unchanged.
F250_PREFIX = "/opt/f250"

do_install() {
    install -d ${D}${F250_PREFIX}/bin
    for b in vehicle-gateway recorder obd-console power-manager camera-manager camera-ctl; do
        install -m 0755 ${B}/target/${CARGO_TARGET_SUBDIR}/$b ${D}${F250_PREFIX}/bin/
    done

    # The gateway's runtime data (agl/rootfs/opt/f250/libexec/gateway-start).
    install -d ${D}${F250_PREFIX}/share/data
    cp -R --no-preserve=ownership ${S}/shared/signals ${D}${F250_PREFIX}/share/data/signals
    cp -R --no-preserve=ownership ${S}/simulator/powerstroke/scenarios ${D}${F250_PREFIX}/share/data/scenarios
    install -m 0644 ${S}/apps/infotainment/assets/config/warning_rules.json ${D}${F250_PREFIX}/share/data/
}

FILES:${PN} = "${F250_PREFIX}/bin ${F250_PREFIX}/share/data"
