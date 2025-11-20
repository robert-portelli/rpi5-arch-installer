# 'config' is provided by src/lib/_config.bash sourced in main.bash.
# shellcheck disable=SC2154

log_info "Stage 20: mount target filesystem hierarchy"

# Ensure root mountpoint exists on host
log_debug "Ensuring root mountpoint exists at ${config[ROOT_MNT]}"
install -d "${config[ROOT_MNT]}"

# Mount root (by PARTUUID)
if ! mountpoint -q "${config[ROOT_MNT]}"; then
    log_info "Mounting root partition UUID=${config[ROOT_UUID]} at ${config[ROOT_MNT]}"
    mount "/dev/disk/by-partuuid/${config[ROOT_UUID]}" "${config[ROOT_MNT]}" \
        || die "ROOT UUID '${config[ROOT_UUID]}' could not be mounted to ${config[ROOT_MNT]}"
else
    log_debug "Root already mounted at ${config[ROOT_MNT]}, skipping mount"
fi

# Create ESP mountpoint inside the mounted root
log_debug "Ensuring ESP mountpoint exists at ${config[ESP_MNT]}"
install -d "${config[ESP_MNT]}"

# Mount ESP (by PARTUUID)
if ! mountpoint -q "${config[ESP_MNT]}"; then
    log_info "Mounting ESP partition UUID=${config[ESP_UUID]} at ${config[ESP_MNT]}"
    mount "/dev/disk/by-partuuid/${config[ESP_UUID]}" "${config[ESP_MNT]}" \
        || die "ESP UUID '${config[ESP_UUID]}' could not be mounted to ${config[ESP_MNT]}"
else
    log_debug "ESP already mounted at ${config[ESP_MNT]}, skipping mount"
fi

log_info "Stage 20: mount completed successfully"
