#!/bin/bash -e
install -d -m 755 "${ROOTFS_DIR}/etc/systemd/system.conf.d"
install -m 644 files/watchdog.conf \
	"${ROOTFS_DIR}/etc/systemd/system.conf.d/carbide-watchdog.conf"
install -d -m 755 "${ROOTFS_DIR}/etc/systemd/journald.conf.d"
install -m 644 files/journald.conf \
	"${ROOTFS_DIR}/etc/systemd/journald.conf.d/carbide-volatile.conf"

# The hardware watchdog has to be handed to the kernel before systemd can pet
# it. On a read-only root this is the only chance to say so.
CONFIG_TXT="${ROOTFS_DIR}/boot/firmware/config.txt"
if ! grep -q '^dtparam=watchdog=on' "${CONFIG_TXT}"; then
	printf '\n# Carbide Motion Kiosk\ndtparam=watchdog=on\n' >> "${CONFIG_TXT}"
fi

on_chroot << 'CHROOT'
set -e
# /var/log is on the read-only overlay, so the persistent journal is pointed
# at the data partition. The directory is created by carbide-firstboot.
rm -rf /var/log/journal
ln -sfn /data/log/journal /var/log/journal
# Swap on an SD card is both slow and a corruption surface, and Carbide Motion
# does not need it.
systemctl disable dphys-swapfile.service 2>/dev/null || true
if command -v dphys-swapfile >/dev/null 2>&1; then
	dphys-swapfile swapoff 2>/dev/null || true
	dphys-swapfile uninstall 2>/dev/null || true
fi

# Nothing on this image benefits from these, and both write to disk.
systemctl disable apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
systemctl disable man-db.timer 2>/dev/null || true

sed -i -E 's|(\s/\s+ext4\s+)defaults|\1defaults,noatime|' /etc/fstab
CHROOT
