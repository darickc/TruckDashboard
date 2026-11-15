SUMMARY = "eSpeak NG at the commit Piper 1.8.0 pins: libpiper's phonemizer"
DESCRIPTION = "eSpeak NG as libpiper builds it (ADR-0048), for the piper \
recipe: the target build gives the static libespeak-ng and libucd that \
libpiper links; the native build compiles espeak-ng-data, which piper \
installs. Not a general espeak-ng: no shared library, no audio output, \
nothing of it on its own in the image."
HOMEPAGE = "https://github.com/espeak-ng/espeak-ng"

# eSpeak NG is GPL-3.0-or-later (README "License Information"), ucd-tools
# too; ucd-tools' Unicode data tables are under the Unicode licence
# (COPYING.UCD, the 1991-2018 notice: Unicode-DFS-2016). COPYING.BSD2 and
# COPYING.APACHE cover Windows' getopt.c and other files not built here.
LICENSE = "GPL-3.0-or-later & Unicode-DFS-2016"
LIC_FILES_CHKSUM = " \
    file://COPYING;md5=d32239bcb673463ab874e80d47fae504 \
    file://COPYING.UCD;md5=9bc437a2583c6de495e5c4acd7c2c787 \
"

# espeak-ng 1.52.0.1 at the commit libpiper/CMakeLists.txt pins (v1.8.0:
# "2025-Mar-22"). sonic: espeak-ng's cmake/deps.cmake fetches it at
# configure time whatever USE_LIBSONIC says, so it is fetched here and
# handed over (FETCHCONTENT_SOURCE_DIR_SONIC-GIT); with USE_LIBSONIC=OFF
# nothing of it is linked.
SRC_URI = "git://github.com/espeak-ng/espeak-ng.git;protocol=https;nobranch=1 \
           git://github.com/waywardgeek/sonic.git;protocol=https;nobranch=1;name=sonic;destsuffix=sonic"
SRCREV = "212928b394a96e8fd2096616bfd54e17845c48f6"
SRCREV_sonic = "fbf75c3d6d846bad3bb3d456cbc5d07d9fd8c104"
SRCREV_FORMAT = "default_sonic"

inherit cmake

# libpiper's ExternalProject options (v1.8.0), without EXTRA_cmn/EXTRA_ru:
# those only add the big Chinese and Russian dictionaries, and the head unit
# speaks English. espeak-ng compiles its data only when not cross-compiling
# (its CMakeLists.txt), so the target build is the library alone and the
# native build makes the data with the program it builds. The data is the
# same on both: little-endian aarch64 here and on the Pi.
EXTRA_OECMAKE = " \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DUSE_ASYNC=OFF \
    -DUSE_MBROLA=OFF \
    -DUSE_LIBSONIC=OFF \
    -DUSE_LIBPCAUDIO=OFF \
    -DUSE_KLATT=OFF \
    -DUSE_SPEECHPLAYER=OFF \
    -DENABLE_TESTS=OFF \
    -DFETCHCONTENT_FULLY_DISCONNECTED=ON \
    -DFETCHCONTENT_SOURCE_DIR_SONIC-GIT=${UNPACKDIR}/sonic \
"
CFLAGS:append = " -D_FILE_OFFSET_BITS=64"

# espeak-ng installs libespeak-ng.a but not ucd-tools' libucd.a, which
# libpiper links beside it. Its Vim syntax files go.
do_install:append() {
    install -m 0644 ${B}/src/ucd-tools/libucd.a ${D}${libdir}/
    rm -rf ${D}${datadir}/vim
    rmdir --ignore-fail-on-non-empty ${D}${datadir}
}

# The target's espeak-ng program isn't used (the native one compiled the
# data), so it isn't kept.
do_install:append:class-target() {
    rm -rf ${D}${bindir}
}

# The target's static libraries and headers are for piper's build only.
FILES:${PN}-staticdev += "${libdir}/libucd.a"

BBCLASSEXTEND = "native"
