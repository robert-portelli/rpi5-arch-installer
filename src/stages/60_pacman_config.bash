log_info "Stage 60: configure pacman-contrib and hooks"

: "${BASE_DIR:?BASE_DIR must be set}"
: "${config[ROOT_MNT]:?config[ROOT_MNT] must be set}"

arch-chroot "${config[ROOT_MNT]}" pacman --config /etc/pacman.arm.conf.bootstrap \
    -S --quiet --noconfirm \
    pacman-contrib

log_debug "Installing pacman hooks to target"
while IFS= read -r -d '' hook_path; do
    # Filename only (preserves leading dots, spaces, etc.)
    hook_name="$(basename "$hook_path")"

    # Destination inside the mounted root
    target="${config[ROOT_MNT]}/etc/pacman.d/hooks/$hook_name"

    install -D -m0644 "$hook_path" "$target"

    log_debug "Installed $hook_name to $target"
done < <(find "$BASE_DIR/src/assets/pacman/hooks" -maxdepth 1 -type f -print0 | sort -z)

log_debug "Installing systemd units to target and enabling timers"
while IFS= read -r -d '' unit_path; do
    unit_name="$(basename "$unit_path")"

    target="${config[ROOT_MNT]}/etc/systemd/system/$unit_name"

    install -D -m0644 "$unit_path" "$target"

    log_debug "Installed $unit_name to $target"

    if [[ "$unit_name" == *.timer ]]; then
        arch-chroot "${config[ROOT_MNT]}" systemctl enable "$unit_name"
        log_debug "Enabled $unit_name"
    fi
done < <(find "$BASE_DIR/src/assets/pacman/units" -maxdepth 1 -type f -print0 | sort -z)

log_debug "Installing pacman helper binaries to target"
while IFS= read -r -d '' bin_path; do
    bin_name="$(basename "$bin_path")"

    target="${config[ROOT_MNT]}/usr/local/sbin/$bin_name"

    install -D -m0755 "$bin_path" "$target"

    log_debug "Installed $bin_name to $target"
done < <(find "$BASE_DIR/src/assets/pacman/bin" -maxdepth 1 -type f -print0 | sort -z)
