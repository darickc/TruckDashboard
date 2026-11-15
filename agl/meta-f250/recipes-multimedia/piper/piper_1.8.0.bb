SUMMARY = "Piper text to speech: libpiper, onnxruntime and espeak-ng-data for f250-tts"
DESCRIPTION = "Piper 1.8.0's libpiper (OHF-Voice/piper1-gpl), the \
spoken directions' voice engine (ADR-0048), in /opt/f250/piper as \
libpiper's own CMake install lays it out: lib/libpiper.so, \
lib/libonnxruntime.so*, share/espeak-ng-data. services/tts loads it at run \
time; the voice is piper-voice-en-us-ljspeech."
HOMEPAGE = "https://github.com/OHF-Voice/piper1-gpl"

# What is in the package: libpiper (GPL-3.0-only, COPYING), with
# nlohmann/json and uni_algo headers compiled in (MIT); espeak-ng linked in
# statically and its compiled data (GPL-3.0-or-later and Unicode-DFS-2016,
# piper-espeak-ng); Microsoft's prebuilt onnxruntime (MIT, with the
# third-party code it contains listed in ThirdPartyNotices.txt, installed
# beside it).
LICENSE = "GPL-3.0-only & MIT & GPL-3.0-or-later & Unicode-DFS-2016 & Onnxruntime-ThirdPartyNotices"
LIC_FILES_CHKSUM = " \
    file://COPYING;md5=8f0e2cd40e05189ec81232da84bd6e1a \
    file://${ORT}/LICENSE;md5=0f7e3b1308cb5c00b372a6e78835732d \
    file://${ORT}/ThirdPartyNotices.txt;md5=e958043c29fba872f89cf708cdd1178d \
"
# Relative to S (the SPDX task joins them).
NO_GENERIC_LICENSE[Onnxruntime-ThirdPartyNotices] = "../onnxruntime-linux-aarch64-${ORT_PV}/ThirdPartyNotices.txt"

# Tag v1.8.0 (2026-09-04). onnxruntime: the prebuilt linux-aarch64 release
# libpiper's own CMakeLists.txt downloads (1.22.0, commit f2174028), the
# library tested on the bench Pi; building onnxruntime from source has no
# recipe in this AGL tree.
ORT_PV = "1.22.0"
ORT = "${UNPACKDIR}/onnxruntime-linux-aarch64-${ORT_PV}"
SRC_URI = "git://github.com/OHF-Voice/piper1-gpl.git;protocol=https;nobranch=1 \
           https://github.com/microsoft/onnxruntime/releases/download/v${ORT_PV}/onnxruntime-linux-aarch64-${ORT_PV}.tgz;name=onnxruntime \
           file://0001-libpiper-espeak-ng-from-the-build-system.patch"
SRCREV = "639388b6317fc4731e91d53da42aea68fd4166ff"
SRC_URI[onnxruntime.sha256sum] = "bb76395092d150b52c7092dc6b8f2fe4d80f0f3bf0416d2f269193e347e24702"

# The prebuilt onnxruntime is aarch64 Linux only.
COMPATIBLE_HOST = "aarch64.*-linux"

DEPENDS = "piper-espeak-ng piper-espeak-ng-native"

inherit cmake

OECMAKE_SOURCEPATH = "${S}/libpiper"

# The install tree tts-start expects (ADR-0048 decision 5).
prefix = "/opt/f250/piper"
exec_prefix = "${prefix}"

# espeak-ng from piper-espeak-ng (the patch above): the target's static
# libraries and headers in the sysroot's /usr, the data from the native
# build. ONNXRUNTIME_DIR: libpiper links the prebuilt library and installs
# its lib/ (cmake/ and pkgconfig/ excluded) beside itself. ONNXRUNTIME_LIB
# is given too: the cross toolchain confines find_library to the sysroot,
# where the unpacked library isn't.
EXTRA_OECMAKE = " \
    -DCMAKE_BUILD_TYPE=Release \
    -DESPEAKNG_DIR=${STAGING_DIR_HOST}/usr \
    -DESPEAKNG_DATA_DIR=${STAGING_DATADIR_NATIVE}/espeak-ng-data \
    -DONNXRUNTIME_DIR=${ORT} \
    -DONNXRUNTIME_LIB=${ORT}/lib/libonnxruntime.so \
"

# onnxruntime's headers are outside S and the sysroots, which Yocto's
# prefix maps cover: map them too, so no build path reaches the debug info.
DEBUG_PREFIX_MAP:append = " -ffile-prefix-map=${ORT}=${TARGET_DBGSRC_DIR}/onnxruntime"

# Only what tts loads: the CLI (piper_exe) and the header are removed;
# onnxruntime's licence notices go beside its library.
do_install:append() {
    rm -rf ${D}${bindir} ${D}${includedir}
    install -m 0644 ${ORT}/LICENSE ${D}${libdir}/onnxruntime-LICENSE
    install -m 0644 ${ORT}/ThirdPartyNotices.txt ${D}${libdir}/onnxruntime-ThirdPartyNotices.txt
}

# libpiper.so has no version and tts dlopens it by that name, so it belongs
# in the main package, with onnxruntime's unversioned link.
FILES_SOLIBSDEV = ""
FILES:${PN} = "${libdir} ${datadir}/espeak-ng-data"
INSANE_SKIP:${PN} += "dev-so"
# Microsoft's library comes stripped and linked with its own flags.
INSANE_SKIP:${PN} += "already-stripped ldflags"
