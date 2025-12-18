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
# Best-effort udev settle (harmless in container)
if command -v udevadm >/dev/null; then
    log_debug "Calling udevadm settle (best-effort)"
    udevadm settle || :
fi

# centralize partition references based on context, i.e., udev env or not
log_info "Setting partition device nodes in config"

## instead of checking for existence of each partuuid, root is arbitrarily chosen
if [[ -b "/dev/disk/by-partuuid/${config[ROOT_UUID]}" ]]; then
    log_info "using existing device nodes"

    config[ESP_NODE]="/dev/disk/by-partuuid/${config[ESP_UUID]}"
    config[ROOT_NODE]="/dev/disk/by-partuuid/${config[ROOT_UUID]}"
else
    log_info "No by-partuuid nodes; creating and registering partition device nodes from sysfs"

    base="$(basename "${config[DISK]}")"
    sys_block="/sys/block/$base"

    log_debug "node-creation: disk=${config[DISK]}"
    log_debug "node-creation: base=${base}"
    log_debug "node-creation: sys_block=${sys_block}"

    if [[ ! -d "$sys_block" ]]; then
        log_error "sysfs path $sys_block not found; did systemd-repart run?"
        return 1
    fi

    log_debug "node-creation: partition dirs under ${sys_block}: $(printf '%s ' "$sys_block"/"$base"p* 2>/dev/null)"

    # 1) Define which config keys we want to populate, in order.
    nodes=(ESP_NODE ROOT_NODE)

    # 2) Collect and sort partition dirs (e.g. /sys/block/loop0/loop0p1, loop0p2, …).
    partitions=()
    for part_dir in "$sys_block"/"$base"p*; do
        [[ -d "$part_dir" ]] || continue
        partitions+=("$part_dir")
    done

    if ((${#partitions[@]} == 0)); then
        log_error "no partitions found under $sys_block; did systemd-repart run?"
        return 1
    fi

    # Sort to ensure stable ordering (loop0p1, loop0p2, …).
    mapfile -t partitions < <(printf '%s\n' "${partitions[@]}" | sort -V)

    if ((${#partitions[@]} < ${#nodes[@]})); then
        log_error "expected at least ${#nodes[@]} partitions on ${config[DISK]}, found ${#partitions[@]}"
        return 1
    fi

    log_info "Creating /dev/${base}pN partition nodes and assigning to config: ${nodes[*]}"

    # 3) For each desired config key, use the corresponding partition in order.
    for i in "${!nodes[@]}"; do
        node_key=${nodes[i]}
        part_dir=${partitions[i]}

        log_debug "processing ${node_key} from part_dir=${part_dir}"

        dev=$(<"$part_dir/dev") || {
            log_error "failed to read $part_dir/dev"
            return 1
        }

        IFS=':' read -r major minor <<<"$dev" || {
            log_error "invalid major:minor '$dev' in $part_dir/dev"
            return 1
        }

        name="$(basename "$part_dir")"
        node="/dev/$name"

        if [[ -b "$node" ]]; then
            log_debug "Partition node $node already exists (major:minor $major:$minor)"
        else
            log_debug "Creating partition node $node (major:minor $major:$minor)"
            if ! mknod "$node" b "$major" "$minor"; then
                log_error "failed to create $node"
                return 1
            fi
        fi

        config["$node_key"]="$node"
        log_debug "assigned config[${node_key}]=${node}"
    done
fi

# format the esp
log_info "Formatting ESP at ${config[ESP_NODE]} as FAT32"
mkfs.vfat -F 32 -n ESP "${config[ESP_NODE]}"

log_info "Stage 10: partitioning and ESP formatting complete"
