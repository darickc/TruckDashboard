# Our config.txt block (agl/boot/config-f250.txt): the 7" DSI panel and the
# commented HAT lines. Stage 1 appends it on the Pi (stage1-setup.sh step 2);
# here it goes in at build time, in the same form, so `stage1-setup.sh
# --check` finds the current block on a meta-f250 image too.
#
# The file comes from agl/boot/ beside this layer. agl-build.sh refuses to
# build from a checkout with uncommitted changes, so it matches the commit
# the rest of the image is built from.

FILESEXTRAPATHS:prepend := "${THISDIR}/../../../boot:"
SRC_URI += "file://config-f250.txt"

# After do_deploy and every append to it (meta-agl-bsp adds its own lines),
# so the block comes last, after one blank line, as stage1-setup.sh writes it.
f250_config_txt() {
    cfg=${DEPLOYDIR}/${BOOTFILES_DIR_NAME}/config.txt
    sed '/^# >>> f250/,/^# <<< f250/d' "$cfg" \
        | awk '{ l[NR] = $0 } END { n = NR; while (n > 0 && l[n] == "") n--; for (i = 1; i <= n; i++) print l[i] }' >"$cfg.new"
    echo >>"$cfg.new"
    cat ${UNPACKDIR}/config-f250.txt >>"$cfg.new"
    mv "$cfg.new" "$cfg"
}
do_deploy[postfuncs] += "f250_config_txt"
