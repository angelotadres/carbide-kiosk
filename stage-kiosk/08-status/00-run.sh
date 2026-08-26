#!/bin/bash -e
install -m 755 files/carbide-kiosk-status \
	"${ROOTFS_DIR}/usr/local/sbin/carbide-kiosk-status"
install -m 755 files/carbide-kiosk-saver-text \
	"${ROOTFS_DIR}/usr/local/bin/carbide-kiosk-saver-text"
install -m 644 files/carbide-kiosk-status.service \
	"${ROOTFS_DIR}/etc/systemd/system/carbide-kiosk-status.service"
install -m 644 files/carbide-kiosk-status.timer \
	"${ROOTFS_DIR}/etc/systemd/system/carbide-kiosk-status.timer"

on_chroot << 'CHROOT'
set -e
systemctl enable carbide-kiosk-status.timer
CHROOT
