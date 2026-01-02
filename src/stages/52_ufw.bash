# 'config' is provided by src/lib/_config.bash sourced in main.bash.
# shellcheck disable=SC2154

log_info "Stage 52: firewall (ufw base install and first-boot finalization)"

# ----------------------------------------------------------------------
# Install UFW into the target
# ----------------------------------------------------------------------
log_debug "Installing ufw into target"
arch-chroot "${config[ROOT_MNT]}" pacman --config /etc/pacman.arm.conf.bootstrap -S --quiet --noconfirm ufw \
    || die "Failed to install ufw in target"

# ----------------------------------------------------------------------
# Enable ufw.service (but do not start it yet)
# ----------------------------------------------------------------------
log_debug "Enabling ufw.service (deferred activation)"
arch-chroot "${config[ROOT_MNT]}" systemctl enable ufw.service \
    || die "Failed to enable ufw.service"

# ----------------------------------------------------------------------
# Install first-boot firewall finalization service
# ----------------------------------------------------------------------
log_debug "Installing first-boot firewall finalization unit"

install -D -m0644 \
    "${BASE_DIR}/src/assets/ufw/ufw-firstboot.service" \
    "${config[ROOT_MNT]}/usr/lib/systemd/system/ufw-firstboot.service" \
    || die "Failed to install ufw-firstboot.service"

install -D -m0755 \
    "${BASE_DIR}/src/assets/ufw/ufw-firstboot.bash" \
    "${config[ROOT_MNT]}/usr/local/lib/ufw/ufw-firstboot.bash" \
    || die "Failed to install ufw-firstboot.bash"

systemctl --root="${config[ROOT_MNT]}" enable ufw-firstboot.service

log_info "Stage 52: firewall setup complete (finalization deferred to first boot)"
