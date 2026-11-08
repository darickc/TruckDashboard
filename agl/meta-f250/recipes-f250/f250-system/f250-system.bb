SUMMARY = "F-250 head unit system configuration"
DESCRIPTION = "What agl/scripts/stage1-setup.sh does to the prebuilt image, \
done at build time: the vehicle bus safety overrides (ADR-0015), the f250 \
user, the units and drop-ins from agl/rootfs, the persistent journal, and \
the f250-can and f250-storage tools."

require conf/include/f250-source.inc

inherit useradd allarch

# Stage 1 step 3. agl-driver, which runs the dashboard, joins the group in
# agl-users (agl-users_%.bbappend): it is created there.
USERADD_PACKAGES = "${PN}"
GROUPADD_PARAM:${PN} = "--system f250"
USERADD_PARAM:${PN} = "--system -g f250 -d /var/lib/f250 -M -s /bin/false -c 'F-250 head unit services' f250"

SYSD = "${sysconfdir}/systemd/system"

# Units go where Stage 1 puts them (/etc/systemd/system), so --check compares
# the same paths on both kinds of image. Enabling and masking are the
# symlinks `systemctl enable` and `systemctl mask` would make.
# f250_wants <target> <unit>
f250_wants() {
    install -d ${D}${SYSD}/$1.wants
    ln -sf ../$2 ${D}${SYSD}/$1.wants/$2
}

do_install() {
    # agl/rootfs, as stage1-setup.sh step 4 installs it: helpers executable,
    # everything else 0644.
    (cd ${S}/agl/rootfs && find . -type f) | sort | while read -r f; do
        mode=0644
        case "$f" in ./opt/f250/libexec/*) mode=0755 ;; esac
        install -D -m $mode ${S}/agl/rootfs/$f ${D}/$f
    done

    # Stage 1 step 1, vehicle bus safety (ADR-0015): the demo's KUKSA CAN
    # provider and its vcan helper are masked. The networkd override that
    # leaves can* unmanaged is in agl/rootfs.
    for u in kuksa-can-provider.service can-dev-helper.service; do
        ln -sf /dev/null ${D}${SYSD}/$u
    done

    # Stage 1 step 7. The demo homescreen is left out of the image (agl-f250.bb).
    f250_wants multi-user.target f250-gateway.service
    f250_wants multi-user.target f250-recorder.service
    f250_wants graphical.target f250-dashboard.service
    f250_wants agl-compositor.service f250-dashboard.service

    # Persistent journal (step 4): /var/lib/journal, bind-mounted over the
    # tmpfs journal directory. Its group is set in pkg_postinst.
    f250_wants local-fs.target var-volatile-log-journal.mount
    install -d -m 2755 ${D}${localstatedir}/lib/journal

    # The tools `make deploy` installs, and agl/ for `stage1-setup.sh --check`.
    install -m 0755 ${S}/tools/pi/can.sh ${D}/opt/f250/bin/f250-can
    install -m 0755 ${S}/agl/scripts/storage.sh ${D}/opt/f250/bin/f250-storage
    install -d ${D}/opt/f250/share/agl
    for d in boot flutter rootfs scripts configurations; do
        cp -R --no-preserve=ownership ${S}/agl/$d ${D}/opt/f250/share/agl/
    done

    # Which commit this image's head unit software was built from.
    echo "F250_SRCREV=${F250_SRCREV}" >${D}${sysconfdir}/f250-release
}

pkg_postinst:${PN}() {
    chgrp systemd-journal $D${localstatedir}/lib/journal
}

# Your settings: an upgrade keeps them.
CONFFILES:${PN} = "${sysconfdir}/default/f250"

FILES:${PN} = "${sysconfdir} /opt/f250 ${localstatedir}/lib/journal"

# The scripts are bash; f250-can needs ip (iproute2); --check needs cmp.
RDEPENDS:${PN} = "bash iproute2 diffutils systemd"
