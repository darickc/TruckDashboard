# The WebRTC echo canceller for phone calls (ADR-0045 decision 3, spike S3).
# AGL's pipewire_1.%.bbappend (meta-agl/meta-pipewire) replaces
# PACKAGECONFIG:class-target without webrtc-echo-cancelling, so the image had
# only the null canceller (libspa-aec-null.so). meta-oe's pipewire_1.6.8.bb
# has the option: -Decho-cancel-webrtc=enabled, building against
# webrtc-audio-processing-2 (2.1, meta-multimedia). It adds
# ${libdir}/spa-0.2/aec/libspa-aec-webrtc.so, split by the recipe into
# pipewire-spa-plugins-aec-webrtc (agl-f250-base.inc installs it by name).
PACKAGECONFIG:append:class-target = " webrtc-echo-cancelling"
