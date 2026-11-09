# The release image, for the truck (ADR-0021): the development image without
# what agl-devel adds to images. Root's password is locked and SSH takes root
# only with the key from F250_AUTHORIZED_KEYS (OpenSSH's default,
# PermitRootLogin prohibit-password); no debug or profiling tools, no package
# manager.
#
# agl-devel stays a distro feature of the build (local.conf), because taking
# it out would rebuild nearly every recipe. What it still changes in this
# image: agl-compositor runs with --debug (its debug protocol, local only)
# and systemd keeps core dumps.
require agl-f250-base.inc

SUMMARY = "F-250 head unit image, release (AGL Flutter)"

IMAGE_FEATURES:remove = " \
    allow-empty-password \
    empty-root-password \
    allow-root-login \
    post-install-logging \
    tools-debug \
    tools-profile \
    package-management \
"
# agl-devel's packages, and screen and mc, which agl-demo.inc (local.conf)
# adds to every image.
IMAGE_INSTALL:remove = "packagegroup-agl-core-devel libdrm-tests weston-examples screen mc"
FEATURE_PACKAGES_selinux = "packagegroup-agl-core-selinux"

python () {
    if not d.getVar("F250_AUTHORIZED_KEYS"):
        raise bb.parse.SkipRecipe("F250_AUTHORIZED_KEYS is not set: without a key nobody can log in (agl-build.sh sets it from F250_SSH_KEY)")
}
