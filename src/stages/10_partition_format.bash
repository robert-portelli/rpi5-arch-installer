# 'config' is provided by src/lib/_config.bash sourced in main.bash.
# shellcheck disable=SC2154

log_info "Stage 10: partition and format disk ${config[DISK]}"

# Layout declarations
log_debug "Cleaning and creating /run/repart.d"
rm -rf /run/repart.d
install -d /run/repart.d

log_debug "Writing repart definition for ESP (UUID=${config[ESP_UUID]})"
cat >/run/repart.d/10-esp.conf <<EOF
[Partition]
Type=esp
Label=ESP
UUID=${config[ESP_UUID]}
SizeMinBytes=1G
SizeMaxBytes=1G
Minimize=off
EOF

log_debug "Writing repart definition for root (UUID=${config[ROOT_UUID]})"
cat >/run/repart.d/20-root.conf <<EOF
[Partition]
Type=root-arm64
Label=root
UUID=${config[ROOT_UUID]}
Format=btrfs
EOF

# Apply partitioning (idempotent)
log_info "Running systemd-repart on ${config[DISK]} (EMPTY=${config[EMPTY]})"
systemd-repart \
    --pretty=yes \
    --definitions=/run/repart.d \
    --dry-run=no \
    --empty="${config[EMPTY]}" \
    "${config[DISK]}"

log_debug "Informing kernel of partition table changes with partprobe"
partprobe "${config[DISK]}"

log_debug "Waiting for ESP and root PARTUUIDs to appear"
udevadm settle --exit-if-exists="/dev/disk/by-partuuid/${config[ESP_UUID]}"
udevadm settle --exit-if-exists="/dev/disk/by-partuuid/${config[ROOT_UUID]}"

# format the esp
log_info "Formatting ESP at /dev/disk/by-partuuid/${config[ESP_UUID]} as FAT32"
mkfs.vfat -F 32 -n ESP "/dev/disk/by-partuuid/${config[ESP_UUID]}"

log_info "Stage 10: partitioning and ESP formatting complete"
