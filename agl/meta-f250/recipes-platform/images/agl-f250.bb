# The head unit image: AGL's Flutter demo image (the one Stage 1 starts from,
# booted and checked on the Pi), with the F-250 software in place of the demo
# homescreen. The demo's other apps stay for now; trimming them is a later
# step, once this image has booted.
require recipes-platform/images/agl-ivi-demo-flutter.bb

SUMMARY = "F-250 head unit image (AGL Flutter)"

# One homescreen per compositor run: agl-compositor 0.0.24 aborts on a second
# one (ADR-0016 addendum), so the demo's is not installed at all.
AGL_APPS_INSTALL:remove = "flutter-ics-homescreen"

IMAGE_INSTALL += " \
    f250-system \
    f250-services \
    f250-dashboard \
"
