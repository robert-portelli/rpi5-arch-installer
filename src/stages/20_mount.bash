#'config' is provided by src/lib/_config.bash sourced in main.bash.
# shellcheck disable=SC2154

# Ensure root mountpoint exists on host
install -d "${config[ROOT_MNT]}"

# Mount root (by PARTUUID)
if ! mountpoint -q "${config[ROOT_MNT]}"; then
    mount "/dev/disk/by-partuuid/${config[ROOT_UUID]}" "${config[ROOT_MNT]}" \
    || { echo "ERROR: ROOT UUID '${config[ROOT_UUID]}' not mounted to ${config[ROOT_MNT]}" >&2; exit 1; }
fi

# Create ESP mountpoint inside the mounted root
install -d "${config[ROOT_MNT]}/boot"

# Mount ESP (by PARTUUID)
if ! mountpoint -q "${config[ESP_MNT]}"; then
    mount "/dev/disk/by-partuuid/${config[ESP_UUID]}" "${config[ESP_MNT]}"\
    || { echo "ERROR: ESP UUID '${config[ESP_UUID]}' not mounted to ${config[ESP_MNT]}" >&2; exit 1; }
fi
