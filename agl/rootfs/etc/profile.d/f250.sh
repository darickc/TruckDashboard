# F-250 head unit tools on the AGL image (installed by agl/scripts/stage1-setup.sh).
# f250-can: tools/pi/can.sh. obd-console talks to the gateway's AGL socket.
PATH="$PATH:/opt/f250/bin"
alias obd-console='/opt/f250/bin/obd-console --gateway unix:/run/f250/vehicle.sock'
