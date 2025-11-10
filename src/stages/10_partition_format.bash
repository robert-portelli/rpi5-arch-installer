#'config' is provided by src/lib/_config.bash sourced in main.bash.
# shellcheck disable=SC2154

# Layout declarations
rm -rf /run/repart.d
install -d /run/repart.d

cat >/run/repart.d/10-esp.conf <<EOF
[Partition]
Type=esp
Label=ESP
UUID=${config[ESP_UUID]}
SizeMinBytes=1G
SizeMaxBytes=1G
Minimize=off
EOF

cat >/run/repart.d/20-root.conf <<EOF
[Partition]
Type=root-arm64
Label=root
UUID=${config[ROOT_UUID]}
Format=btrfs
EOF

# Apply partitioning (idempotent)
systemd-repart \
    --pretty=yes \
    --definitions=/run/repart.d \
    --dry-run=no \
    --empty="${config[EMPTY]}"\
    "${config[DISK]}"

partprobe "${config[DISK]}"
udevadm settle --exit-if-exists="/dev/disk/by-partuuid/${config[ESP_UUID]}"
udevadm settle --exit-if-exists="/dev/disk/by-partuuid/${config[ROOT_UUID]}"

# format the esp
mkfs.vfat -F 32 -n ESP "/dev/disk/by-partuuid/${config[ESP_UUID]}"
