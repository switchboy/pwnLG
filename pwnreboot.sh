#!/bin/sh
# pwnLG reboot helper — run on the TV as root AFTER the Developer Mode app was uninstalled.
sync
/usr/bin/luna-send -n 1 -a com.webos.service.secondscreen.gateway \
  luna://com.webos.service.sleep/shutdown/machineReboot '{"reason":"remoteKey"}'
