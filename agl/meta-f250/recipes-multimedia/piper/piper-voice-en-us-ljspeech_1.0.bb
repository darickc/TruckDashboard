SUMMARY = "Piper voice en_US-ljspeech-medium for the spoken directions"
DESCRIPTION = "The voice the owner chose on the bench (ADR-0048, \
2026-11-15): Piper's en_US ljspeech, medium quality, 22050 Hz, in \
/opt/f250/piper/voices where tts-start looks for it."
HOMEPAGE = "https://huggingface.co/rhasspy/piper-voices"

# Its model card: "License: public domain" (the LJ Speech dataset).
LICENSE = "PD"
LIC_FILES_CHKSUM = "file://${UNPACKDIR}/piper-voice-en_US-ljspeech-medium-MODEL_CARD;md5=5ad31d314786587d4f97effb0b716d61"

# rhasspy/piper-voices at a fixed revision (main on 2026-11-15), so the URLs
# don't move; the checksums are the files tested on the bench Pi.
VOICE_REV = "e9ab671f2a0e50a701b34361136ba3e6a3a9eb0c"
VOICE_URL = "https://huggingface.co/rhasspy/piper-voices/resolve/${VOICE_REV}/en/en_US/ljspeech/medium"
SRC_URI = " \
    ${VOICE_URL}/en_US-ljspeech-medium.onnx;name=onnx \
    ${VOICE_URL}/en_US-ljspeech-medium.onnx.json;name=config \
    ${VOICE_URL}/MODEL_CARD;name=card;downloadfilename=piper-voice-en_US-ljspeech-medium-MODEL_CARD \
"
SRC_URI[onnx.sha256sum] = "6f52a751e2349abe7a76735eb09dc1875298c77ea2342ffd2fef79ff81b87f22"
SRC_URI[config.sha256sum] = "141d612cc0a95ed7efc1ca936b845c2364967f2e9217c5dbfcf69fc4d6c65860"
SRC_URI[card.sha256sum] = "fbee1529c89d36b3fe76d7e9f3f832dce17f44900a52d76a9bda735654766b4d"

S = "${UNPACKDIR}"

inherit allarch

do_configure[noexec] = "1"
do_compile[noexec] = "1"

VOICES = "/opt/f250/piper/voices"

do_install() {
    install -d ${D}${VOICES}
    install -m 0644 ${UNPACKDIR}/en_US-ljspeech-medium.onnx ${D}${VOICES}/
    install -m 0644 ${UNPACKDIR}/en_US-ljspeech-medium.onnx.json ${D}${VOICES}/
}

FILES:${PN} = "${VOICES}"
