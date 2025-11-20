# 'config' is provided by src/lib/_config.bash sourced in main.bash.
# shellcheck disable=SC2154

log_info "Stage 60: applying first-boot system identity to target root at ${config[ROOT_MNT]}"

log_debug "Using locale=${config[LOCALE]}, keymap=${config[KEYMAP]}, timezone=${config[TZ]}, hostname=${config[HOSTNAME]}"

systemd-firstboot \
    --root="${config[ROOT_MNT]}" \
    --locale="${config[LOCALE]}" \
    --keymap="${config[KEYMAP]}" \
    --timezone="${config[TZ]}" \
    --hostname="${config[HOSTNAME]}" \
    --setup-machine-id \
    --delete-root-password --force \
    || die "systemd-firstboot failed to initialize system identity on ${config[ROOT_MNT]}"

log_info "Stage 60: first-boot identity applied successfully"
