#!/bin/bash -e
# Raspberry Pi OS runs raspberrypi-sys-mods/firstboot as init on the very first
# boot, which grows the root partition to fill the whole card and then removes
# itself from cmdline.txt. That leaves nothing for the data partition, so
# carbide-firstboot has no space to work with and refuses to continue.
#
# This is an appliance: the OS is a fixed-size read-only image and every
# remaining byte belongs to the share. So the hook is removed here.
CMDLINE="${ROOTFS_DIR}/boot/firmware/cmdline.txt"
test -f "${CMDLINE}"

sed -i -E 's| init=/usr/lib/raspberrypi-sys-mods/firstboot||g' "${CMDLINE}"

# Drop 'quiet'. First boot takes minutes with nothing else on screen, and a
# frozen-looking display invites someone to power cycle the machine in the
# middle of formatting the card. Boot messages are ugly but they move.
sed -i -E 's| quiet||g' "${CMDLINE}"

# cmdline.txt is read as a single line; a stray newline silently truncates the
# kernel arguments after it.
tr -d '\n' < "${CMDLINE}" > "${CMDLINE}.tmp"
printf '\n' >> "${CMDLINE}.tmp"
mv "${CMDLINE}.tmp" "${CMDLINE}"

if grep -q 'init=' "${CMDLINE}"; then
	echo "09-boot-cmdline: an init= hook survived in cmdline.txt:" >&2
	cat "${CMDLINE}" >&2
	exit 1
fi
test "$(wc -l < "${CMDLINE}")" -eq 1
