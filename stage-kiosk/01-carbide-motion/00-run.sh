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
apt-get install -y --no-install-recommends /tmp/carbidemotion.deb
rm -f /tmp/carbidemotion.deb
test -x /usr/local/bin/carbidemotion
CHROOT
