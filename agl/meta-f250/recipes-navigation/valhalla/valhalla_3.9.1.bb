SUMMARY = "Valhalla routing engine: libvalhalla and valhalla_service, one request per process"
DESCRIPTION = "Valhalla 3.9.1 built for services/navigation (ADR-0035): \
valhalla_service CONFIG ACTION REQUEST answers one request and exits. No \
HTTP service (prime_server), no data tools, no bindings, no tests. Routing \
data is built on the Mac (make route-region) and comes by USB stick."
HOMEPAGE = "https://github.com/valhalla/valhalla"

# What is compiled into valhalla_service: Valhalla itself (MIT), and the
# vendored headers it uses, read at the tag: rapidjson, date,
# unordered_dense, cxxopts, flatbush, cpp-statsd-client (MIT); vtzero and
# protozero (BSD-2-Clause), protozero's varint.hpp from folly (Apache-2.0);
# flatbush's bit_cast from Boost.Core (BSL-1.0); the IANA tz data, compiled
# in (public domain). rapidjson's msinttypes (Windows only) and jsonchecker
# (not built) are left out. libosmium is used only by the data tools.
LICENSE = "MIT & BSD-2-Clause & Apache-2.0 & BSL-1.0 & PD"
LIC_FILES_CHKSUM = " \
    file://COPYING;md5=a6502a7ddd34cba9a24a5a8ef3264e51 \
    file://third_party/rapidjson/license.txt;md5=ba04aa8f65de1396a7e59d1d746c2125 \
    file://third_party/date/LICENSE.txt;md5=b5d973344b3c7bbf7535f0e6e002d017 \
    file://third_party/unordered_dense/LICENSE;md5=1d7f9e1447a1ba175cfd5e005c801e89 \
    file://third_party/cxxopts/LICENSE;md5=8de00431559a76a1b43f6fd44f8f6689 \
    file://third_party/flatbush/LICENSE;md5=a4c42f620dcf3e7eff91a157c2fa59f4 \
    file://third_party/cpp-statsd-client/LICENSE.md;md5=5e042c32f4b43cdb9ceaf4496bbc33be \
    file://third_party/vtzero/LICENSE;md5=f5a2ad01ec9fd3a35d9b615652117a6a \
    file://third_party/protozero/LICENSE.md;md5=bb1a27fdd409f635a3f92106ef78d30a \
    file://third_party/protozero/LICENSE.from_folly;md5=2ee41112a44fe7014dce33e26468ba93 \
    file://third_party/tz/LICENSE;md5=c679c9d6b02bc2757b3eaf8f53c43fba \
"

# Tag 3.9.1 (2026-10-06). gitsm: the vendored headers and the tz data are
# submodules, pinned by the tag's own commit.
SRC_URI = "gitsm://github.com/valhalla/valhalla.git;protocol=https;nobranch=1 \
           file://protoc-native.cmake"
SRCREV = "bafb69902220615a48307d5c790fb6c943802ba4"

inherit cmake pkgconfig

# Boost (headers only, >= 1.71), Protobuf (the lite runtime; protoc runs on
# the build host), zlib. The tz step runs the tz Makefile with awk.
DEPENDS = "boost protobuf protobuf-native zlib"

# valhalla_service is one of ENABLE_TOOLS' programs (with
# valhalla_export_edges and valhalla_expand_bounding_box, which are built
# but not packaged). ENABLE_SERVICES=OFF: no prime_server, so
# valhalla_service has only its one-shot mode. LZ4 is for elevation tiles
# and OSM PBF input, neither used on the head unit. A static libvalhalla:
# nothing else links it, so the image carries one binary. protoc runs on the
# build host: Protobuf's CMake package checks Protobuf_PROTOC_EXECUTABLE, and
# protobuf_generate_cpp runs the protobuf::protoc target, which
# protoc-native.cmake defines. ENABLE_SINGLE_FILES_WERROR=OFF: Valhalla
# builds a few files with -Werror, and this GCC deprecates the
# std::atomic_load/store on shared_ptr that graphreader.cc uses under C++20
# (a warning, not a fault).
EXTRA_OECMAKE = " \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_TOOLS=ON \
    -DENABLE_DATA_TOOLS=OFF \
    -DENABLE_SERVICES=OFF \
    -DENABLE_HTTP=OFF \
    -DENABLE_PYTHON_BINDINGS=OFF \
    -DENABLE_NODE_BINDINGS=OFF \
    -DENABLE_TESTS=OFF \
    -DENABLE_GEOTIFF=OFF \
    -DENABLE_LZ4=OFF \
    -DENABLE_CCACHE=OFF \
    -DENABLE_SINGLE_FILES_WERROR=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DOE_PROTOC=${STAGING_BINDIR_NATIVE}/protoc \
    -DProtobuf_PROTOC_EXECUTABLE=${STAGING_BINDIR_NATIVE}/protoc \
    -DCMAKE_PROJECT_valhalla_INCLUDE=${UNPACKDIR}/protoc-native.cmake \
"

# Only valhalla_service goes in the image (on PATH, where navigation looks
# for it). The other two programs and the Python data scripts Valhalla
# installs into bindir are removed; the headers and the static library stay
# in -dev/-staticdev.
do_install:append() {
    find ${D}${bindir} -mindepth 1 ! -name valhalla_service -delete
}

FILES:${PN} = "${bindir}/valhalla_service"
