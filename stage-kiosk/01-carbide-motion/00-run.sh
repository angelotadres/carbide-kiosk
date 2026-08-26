#!/bin/bash -e
# The package is fetched by build.sh on the host and dropped here. It is
# proprietary and is never committed to this repository.
if [ ! -f files/carbidemotion.deb ]; then
	echo "01-carbide-motion: files/carbidemotion.deb is missing." >&2
	echo "Run build.sh, which calls scripts/fetch-carbide-motion.sh first." >&2
	exit 1
fi

install -m 644 files/carbidemotion.deb "${ROOTFS_DIR}/tmp/carbidemotion.deb"

on_chroot << 'CHROOT'
set -e
# 00-packages already installed every Qt5 dependency the package declares, so
# there is nothing for apt to resolve. dpkg takes the file directly; apt
# refuses it on the command line.
dpkg -i /tmp/carbidemotion.deb || apt-get -y --fix-broken install
rm -f /tmp/carbidemotion.deb
test -x /usr/local/bin/carbidemotion
dpkg-query -W -f='${Status}\n' carbidemotion | grep -q '^install ok installed$'
CHROOT
