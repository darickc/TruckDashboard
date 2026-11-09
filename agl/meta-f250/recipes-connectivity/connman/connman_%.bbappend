# connman 2.0 read netlink into 4096 bytes and lost the end of larger
# messages. On the Pi 5's 16 KiB-page kernel that dropped wlan0 from the
# initial link dump, so Wi-Fi never worked after boot ("connmanctl scan
# wifi": Not implemented). [BENCH] 2026-11-08, bench-log.

FILESEXTRAPATHS:prepend := "${THISDIR}/connman:"
SRC_URI += "file://0001-rtnl-receive-whole-netlink-messages.patch"
