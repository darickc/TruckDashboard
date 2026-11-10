# The development image, for the bench: the head unit plus agl-devel's tools
# (gdb, strace, perf, ...), package management, and root with an empty
# password (agl-devel, from the build's local.conf). Never in the truck: use
# agl-f250-release there (ADR-0021).
require agl-f250-base.inc

SUMMARY = "F-250 head unit image, development (AGL Flutter)"

IMAGE_FEATURES += "package-management"

# Camera bench tools (Phase 6.6): v4l2-ctl and friends, a test pattern
# source, and fpsdisplaysink for measuring the ADR-0009 pipelines.
IMAGE_INSTALL += " \
    v4l-utils \
    gstreamer1.0-plugins-base-videotestsrc \
    gstreamer1.0-plugins-bad-debugutilsbad \
"
