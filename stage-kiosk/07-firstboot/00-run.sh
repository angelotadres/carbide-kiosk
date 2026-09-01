#!/bin/bash -e
install -m 755 files/carbide-firstboot "${ROOTFS_DIR}/usr/local/sbin/carbide-firstboot"
install -m 644 files/carbide-firstboot.service \
	"${ROOTFS_DIR}/etc/systemd/system/carbide-firstboot.service"

# Staged outside every systemd unit directory, on purpose, and installed into
# one by carbide-firstboot once the data partition exists.
#
# Leaving them disabled in /etc/systemd/system is not enough and 1.0.0-alpha.24
# proved it: carbide-kiosk.service, carbide-kiosk-config.service and
# carbide-kiosk-status.service all declare RequiresMountsFor=/data, which pulls
# in whichever mount unit covers that path with a hard Requires - enabled or
# not. On a first boot the partition does not exist yet, so the boot stalled
# ninety seconds on dev-disk-by-label-CARBIDEDATA.device before giving up.
# A unit systemd cannot see cannot be required.
install -d -m 755 "${ROOTFS_DIR}/usr/local/share/carbide-kiosk"
install -m 644 files/data.mount \
	"${ROOTFS_DIR}/usr/local/share/carbide-kiosk/data.mount"
install -m 644 files/var-log-journal.mount \
	"${ROOTFS_DIR}/usr/local/share/carbide-kiosk/var-log-journal.mount"

on_chroot << 'CHROOT'
set -e
systemctl enable carbide-firstboot.service
CHROOT

# The template is copied in by build.sh so that the canonical copy stays at
# config/kiosk.conf.example rather than being duplicated in the stage.
if [ -f files/kiosk.conf.example ]; then
	install -m 644 files/kiosk.conf.example \
		"${ROOTFS_DIR}/boot/firmware/kiosk.conf.example"
fi
