#!/bin/bash -e
install -m 644 files/nftables.conf "${ROOTFS_DIR}/etc/nftables.conf"

on_chroot << 'CHROOT'
set -e
systemctl enable nftables.service
# Samba is the only service this image exposes; nothing else should be
# listening even before the firewall is in force.
systemctl disable ssh.service 2>/dev/null || true
systemctl disable avahi-daemon.service avahi-daemon.socket 2>/dev/null || true
CHROOT
