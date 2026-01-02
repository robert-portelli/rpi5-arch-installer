# 'BASE_DIR' is provided by src/main.bash
# 'config' is provided by src/lib/_config.bash sourced in main.bash.
# shellcheck disable=SC2154

if [[ "${config[ZRAM_SWAP_ENABLE]}" != "1" ]]; then
    log_info "zram-swap disabled; skipping"
    return 0
fi

log_info "Configuring zram swap:"

# ----------------------------------------------------------------------
log_debug "Edit kernel command line: Disabling target's zswap"
# append to the cmdline.txt
(
    file="${config[ESP_MNT]}/cmdline.txt"
    param='zswap.enabled=0'

    [[ -f "$file" ]] || die "ERROR: missing cmdline.txt at: $file"

    line="$(tr '\n' ' ' <"$file" | tr -s ' ' | sed 's/[[:space:]]*$//')"

    if [[ " $line " != *" $param "* ]]; then
        printf '%s %s\n' "$line" "$param" >"$file"
        log_debug "Appended kernel arg: %s" "$param"
    else
        log_debug "Kernel arg already present: %s" "$param"
    fi
)

# ----------------------------------------------------------------------
log_debug "Tune Linux Virtual Memory: Memory Reclaim Behavior"
install -D -m0644 \
  "${BASE_DIR}/src/assets/zram-generator/99-vm-zram.conf" \
  "${config[ROOT_MNT]}/etc/sysctl.d/99-vm-zram.conf"

# ----------------------------------------------------------------------
log_debug "Installing zram-generator on target"
arch-chroot "${config[ROOT_MNT]}" pacman \
    --config /etc/pacman.arm.conf.bootstrap \
    -S --quiet --noconfirm zram-generator \
    || die "Failed to zram-generator in target"

log_debug "Tune Zram-Generator"
install -D -m0644 \
  "${BASE_DIR}/src/assets/zram-generator/10-zram-swap.conf" \
  "${config[ROOT_MNT]}/usr/lib/systemd/zram-generator.conf.d/10-zram-swap.conf"
