# agl-driver runs the dashboard, which connects to the gateway's socket:
# group f250, mode 0770 (f250-gateway.service). stage1-setup.sh step 3 does
# `usermod -aG f250 agl-driver` on the Pi; this does it where the user is
# made. useradd.bbclass runs groupadd, then useradd, then groupmems, so both
# the group and the user exist by then.

GROUPADD_PARAM:${PN} += "--system f250 ;"
GROUPMEMS_PARAM:${PN} = "-a agl-driver -g f250"
