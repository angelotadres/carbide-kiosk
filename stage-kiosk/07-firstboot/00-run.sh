#!/bin/bash -e
install -m 755 files/carbide-firstboot "${ROOTFS_DIR}/usr/local/sbin/carbide-firstboot"
install -m 644 files/carbide-firstboot.service \
	"${ROOTFS_DIR}/etc/systemd/system/carbide-firstboot.service"

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
