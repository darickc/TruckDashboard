# After Next or Previous inside a track (an audiobook's 30 s skip) the phone
# may send nothing, and BlueZ's Position kept counting from the old place
# until a pause. bluetoothd now asks for the play status 1 s after a
# transport key. [BENCH] 2026-11-13, bench-log.

FILESEXTRAPATHS:prepend := "${THISDIR}/bluez5:"
SRC_URI += "file://0001-avrcp-re-read-the-play-status-after-a-transport-key.patch"
