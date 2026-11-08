# The head unit's source: this repository, at one commit.
#
# agl/scripts/agl-build.sh sets both variables in the build's site.conf:
#   F250_REPO    the repository on the build host (in the VM, the Mac's
#                checkout, mounted read-only at the same path)
#   F250_SRCREV  the commit to build (git rev-parse HEAD when the build starts)
# So an image is always built from a commit, never from uncommitted files, and
# the image says which one (/etc/f250-release, from f250-system).

F250_REPO ??= ""
F250_SRCREV ??= ""

LICENSE = "CLOSED"
PV = "0.1+git"

SRC_URI = "git://${F250_REPO};protocol=file;nobranch=1;destsuffix=f250"
SRCREV = "${F250_SRCREV}"
S = "${UNPACKDIR}/f250"

python () {
    if not d.getVar("F250_REPO") or not d.getVar("F250_SRCREV"):
        raise bb.parse.SkipRecipe("F250_REPO and F250_SRCREV are not set: build with agl/scripts/agl-build.sh")
}
