#!/bin/bash -e
install -d -m 755 "${ROOTFS_DIR}/usr/local/lib/carbide-kiosk"
install -m 644 files/usr/local/lib/carbide-kiosk/common.sh \
	"${ROOTFS_DIR}/usr/local/lib/carbide-kiosk/common.sh"
install -m 755 files/usr/local/bin/carbide-kiosk-xsession \
	"${ROOTFS_DIR}/usr/local/bin/carbide-kiosk-xsession"
install -m 755 files/usr/local/sbin/carbide-kiosk-config \
	"${ROOTFS_DIR}/usr/local/sbin/carbide-kiosk-config"
install -m 644 files/carbide-kiosk-config.service \
	"${ROOTFS_DIR}/etc/systemd/system/carbide-kiosk-config.service"
install -m 644 files/carbide-kiosk.service \
	"${ROOTFS_DIR}/etc/systemd/system/carbide-kiosk.service"

# xinit from a systemd service is not a console login, so Xorg needs telling.
install -d -m 755 "${ROOTFS_DIR}/etc/X11"
cat > "${ROOTFS_DIR}/etc/X11/Xwrapper.config" << 'XWRAP'
allowed_users=anybody
needs_root_rights=yes
XWRAP

on_chroot << CHROOT
set -e
if ! id -u kiosk >/dev/null 2>&1; then
	adduser --disabled-password --gecos "Carbide Motion Kiosk" --uid 1000 kiosk
fi
usermod -aG video,render,input,tty,dialout,plugdev kiosk

# pi-gen had to be given a password to build a headless image. Lock it: the
# session is started by systemd, which does not authenticate, so the account
# never needs a usable password. This is what stops the published image from
# shipping a credential.
passwd -l kiosk

# Carbide Motion keeps its settings under the home directory. The root
# filesystem is read-only, so both paths live on the data partition.
rm -rf /home/kiosk/.config /home/kiosk/.local/share
install -d -m 755 -o kiosk -g kiosk /home/kiosk/.local
ln -sfn /data/kiosk/config /home/kiosk/.config
ln -sfn /data/kiosk/share /home/kiosk/.local/share
chown -h kiosk:kiosk /home/kiosk/.config /home/kiosk/.local/share

systemctl enable carbide-kiosk-config.service
systemctl enable carbide-kiosk.service
systemctl set-default multi-user.target
CHROOT
