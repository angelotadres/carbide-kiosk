#!/bin/bash -e
install -d -m 755 "${ROOTFS_DIR}/usr/local/lib/carbide-kiosk"
install -m 644 files/usr/local/lib/carbide-kiosk/common.sh \
	"${ROOTFS_DIR}/usr/local/lib/carbide-kiosk/common.sh"
install -m 755 files/usr/local/bin/carbide-kiosk-xsession \
	"${ROOTFS_DIR}/usr/local/bin/carbide-kiosk-xsession"
install -m 755 files/usr/local/bin/carbide-kiosk-write-xscreensaver \
	"${ROOTFS_DIR}/usr/local/bin/carbide-kiosk-write-xscreensaver"
install -m 755 files/usr/local/bin/carbide-kiosk-keyboard \
	"${ROOTFS_DIR}/usr/local/bin/carbide-kiosk-keyboard"

# The launcher button that shows and hides the keyboard.
install -d -m 755 "${ROOTFS_DIR}/etc/xdg/carbide"
install -m 644 files/launcher/carbide-keyboard.desktop \
	"${ROOTFS_DIR}/etc/xdg/carbide/carbide-keyboard.desktop"
install -m 644 files/launcher/tint2rc "${ROOTFS_DIR}/etc/xdg/carbide/tint2rc"

# openbox rules: Carbide Motion maximised and undecorated, keyboard above it.
install -d -m 755 "${ROOTFS_DIR}/etc/xdg/openbox"
install -m 644 files/openbox/rc.xml "${ROOTFS_DIR}/etc/xdg/openbox/rc.xml"

install -m 755 files/usr/local/sbin/carbide-kiosk-access \
	"${ROOTFS_DIR}/usr/local/sbin/carbide-kiosk-access"
install -m 755 files/usr/local/sbin/carbide-kiosk-config \
	"${ROOTFS_DIR}/usr/local/sbin/carbide-kiosk-config"
install -m 644 files/carbide-kiosk-access.service \
	"${ROOTFS_DIR}/etc/systemd/system/carbide-kiosk-access.service"
install -m 644 files/carbide-kiosk-config.service \
	"${ROOTFS_DIR}/etc/systemd/system/carbide-kiosk-config.service"
install -m 644 files/carbide-kiosk.service \
	"${ROOTFS_DIR}/etc/systemd/system/carbide-kiosk.service"
install -d -m 755 "${ROOTFS_DIR}/etc/systemd/system/getty@tty2.service.d"
install -m 644 files/getty-autologin.conf \
	"${ROOTFS_DIR}/etc/systemd/system/getty@tty2.service.d/autologin.conf"

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

# pi-gen had to be given a password to build a headless image. Replace it with
# '*', which no password can ever match. The session is started by systemd and
# the rescue console by agetty --autologin, neither of which authenticates, so
# the account never needs a usable password. This is what stops the published
# image from shipping a credential.
usermod -p '*' kiosk

# Ctrl+Alt+F2 gives a console to someone physically at the machine. There is
# no network shell at all, by design.
systemctl enable getty@tty2.service

# Carbide Motion keeps its settings under the home directory. The root
# filesystem is read-only, so both paths live on the data partition.
rm -rf /home/kiosk/.config /home/kiosk/.local/share
install -d -m 755 -o kiosk -g kiosk /home/kiosk/.local
ln -sfn /data/kiosk/config /home/kiosk/.config
ln -sfn /data/kiosk/share /home/kiosk/.local/share
chown -h kiosk:kiosk /home/kiosk/.config /home/kiosk/.local/share

# Applications write here; root-owned would silently break them.
install -d -m 700 -o kiosk -g kiosk /home/kiosk/.cache

# Somewhere obvious for the file dialog to land, pointing at the share.
ln -sfn /data/gcode /home/kiosk/gcode
chown -h kiosk:kiosk /home/kiosk/gcode

systemctl enable carbide-kiosk-access.service
systemctl enable carbide-kiosk-config.service
systemctl enable carbide-kiosk.service
systemctl set-default multi-user.target
CHROOT
