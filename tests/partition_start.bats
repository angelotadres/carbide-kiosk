#!/usr/bin/env bats
# The data partition is created once, on a machine nobody is watching, from
# parted output. Getting the start offset wrong produced a 1 MiB partition at
# the far end of a 233 GB card and stranded everything in between, so the
# arithmetic is pinned here against real captured output.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CARBIDE_KIOSK_LIB="$REPO_ROOT/stage-kiosk/02-kiosk-session/files/usr/local/lib/carbide-kiosk"
  source "$REPO_ROOT/stage-kiosk/07-firstboot/files/carbide-firstboot"
}

# Captured from the Pi that failed: 512 MiB boot, 2456 MiB root, rest free.
real_output() {
  cat <<'OUT'
BYT;
/dev/mmcblk0:238800MiB:sd/mmc:512:512:msdos:SD SC64G:;
1:8.00MiB:520MiB:512MiB:fat32::lba;
2:520MiB:2976MiB:2456MiB:ext4::;
OUT
}

@test "starts one MiB past the end of the last partition" {
  run bash -c 'real_output() { cat <<'"'"'OUT'"'"'
BYT;
/dev/mmcblk0:238800MiB:sd/mmc:512:512:msdos:SD SC64G:;
1:8.00MiB:520MiB:512MiB:fat32::lba;
2:520MiB:2976MiB:2456MiB:ext4::;
OUT
}; source '"$REPO_ROOT"'/stage-kiosk/07-firstboot/files/carbide-firstboot; real_output | data_partition_start_mb'
  [ "$output" = "2977" ]
}

@test "the header lines are not mistaken for partitions" {
  run bash -c 'source '"$REPO_ROOT"'/stage-kiosk/07-firstboot/files/carbide-firstboot
printf "BYT;\n/dev/mmcblk0:238800MiB:sd/mmc:512:512:msdos:SD SC64G:;\n1:8.00MiB:520MiB:512MiB:fat32::lba;\n" | data_partition_start_mb'
  [ "$output" = "521" ]
}

@test "an empty partition table yields nothing rather than zero" {
  run bash -c 'source '"$REPO_ROOT"'/stage-kiosk/07-firstboot/files/carbide-firstboot
printf "BYT;\n/dev/mmcblk0:238800MiB:sd/mmc:512:512:msdos:SD SC64G:;\n" | data_partition_start_mb'
  [ -z "$output" ]
}

@test "the highest end wins even when partitions are listed out of order" {
  run bash -c 'source '"$REPO_ROOT"'/stage-kiosk/07-firstboot/files/carbide-firstboot
printf "2:520MiB:2976MiB:2456MiB:ext4::;\n1:8.00MiB:520MiB:512MiB:fat32::lba;\n" | data_partition_start_mb'
  [ "$output" = "2977" ]
}

@test "mmcblk partitions take a p, sd partitions do not" {
  run partition_device /dev/mmcblk0 3
  [ "$output" = "/dev/mmcblk0p3" ]
  run partition_device /dev/sda 3
  [ "$output" = "/dev/sda3" ]
}
