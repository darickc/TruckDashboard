# What both head unit images have (ADR-0021): AGL's compositor image plus
# the F-250 software and what it needs, and nothing of the demo's.
#
# agl-image-compositor (meta-agl-core) gives the boot and machine packages,
# connman, agl-compositor and
# agl-users (agl-driver). The demo image added on top of it: KUKSA and the
# HVAC, radio and audio-mixer services, Qt and the navigation demo, gpsd,
# oFono, rtl-sdr, mpd, text-to-speech, the CJK fonts, applaunchd and the demo
# apps. None of those is used here; each Phase 6 feature brings what it needs
# (PipeWire with the audio manager, gpsd with GPS).
require recipes-platform/images/agl-image-compositor.bb

# No "splash" feature: AGL removes it on the Pi (agl_raspberrypi.inc). The boot
# splash comes from psplash-portrait-config, which pulls in psplash, as on
# the demo image.
IMAGE_FEATURES += "ssh-server-openssh"

IMAGE_INSTALL += " \
    weston-ini-conf-flutter \
    psplash-portrait-config \
    ttf-dejavu-sans \
    ttf-dejavu-sans-mono \
    bluez5 \
    avahi-daemon \
    rsync \
    f250-system \
    f250-services \
    f250-dashboard \
    gstreamer1.0-plugins-good-video4linux2 \
    gstreamer1.0-plugins-good-jpeg \
    gstreamer1.0-plugins-base-videoconvertscale \
    gstreamer1.0-plugins-bad-waylandsink \
"

# weston-ini-conf-flutter: the compositor's configuration for flutter-auto
# (agl-compositor-init needs some weston-ini; this is the one the Flutter
# demo used). The dashboard has no fonts of its own, so the system's sans
# (DejaVu) draws it. bluez5: the gateway reaches the MX+ over RFCOMM. rsync:
# `make deploy` copies with it. avahi-daemon: the Pi answers as
# raspberrypi5.local (the demo image got avahi only through PipeWire).
#
# GStreamer for the cameras (Phase 6.6, camera-policy.md): v4l2src for UVC
# cameras, jpegdec for their MJPEG, videoconvert/videoscale, and waylandsink:
# camera-manager shows each camera in a window of its own (ADR-0009, accepted
# 2026-11-09). appsink, the Flutter-texture option's sink, left with that
# decision. Names from the 22.0.1 demo image's manifest.

# root's SSH key, from the build host (agl-build.sh puts the file's path in
# site.conf). Root logs in with it; the release image has no other way in
# over the network.
F250_AUTHORIZED_KEYS ??= ""
ROOTFS_POSTPROCESS_COMMAND += "${@'f250_root_authorized_keys ' if d.getVar('F250_AUTHORIZED_KEYS') else ''}"
do_rootfs[file-checksums] += "${@'%s:True' % d.getVar('F250_AUTHORIZED_KEYS') if d.getVar('F250_AUTHORIZED_KEYS') else ''}"

f250_root_authorized_keys() {
    install -d -m 0700 ${IMAGE_ROOTFS}${ROOT_HOME}/.ssh
    install -m 0600 ${F250_AUTHORIZED_KEYS} ${IMAGE_ROOTFS}${ROOT_HOME}/.ssh/authorized_keys
}

# oFono comes with connman (its 3g option) and its package enables it as it
# is installed. OE's own preset step runs in enable-only mode, so the disable
# line in 00-f250.preset can't undo that here: disable it explicitly. Nothing
# D-Bus-activates it, so disabled is off.
ROOTFS_POSTPROCESS_COMMAND += "f250_disable_units "
f250_disable_units() {
    systemctl --root="${IMAGE_ROOTFS}" disable ofono.service
}
