#!/bin/bash -e
# smb.conf itself is generated at every boot by carbide-kiosk-config, because
# /etc does not survive the read-only overlay. This stage only makes sure the
# services exist and start in the right order.
on_chroot << 'CHROOT'
set -e
systemctl enable smbd.service
systemctl enable nmbd.service
CHROOT
