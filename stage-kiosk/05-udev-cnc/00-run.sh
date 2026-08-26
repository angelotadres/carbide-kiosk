#!/bin/bash -e
install -m 644 files/60-carbide-cnc.rules \
	"${ROOTFS_DIR}/etc/udev/rules.d/60-carbide-cnc.rules"
