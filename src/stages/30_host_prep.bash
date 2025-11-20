#'config' is provided by src/lib/_config.bash sourced in main.bash.
# shellcheck disable=SC2154

log_info "Stage 30: host preparation (ALARM key, qemu, pacman config)"

# --- Import Arch Linux ARM builder key on the LIVE ISO (host pacman) ---
log_info "Installing required host tools: gnupg, archlinux-keyring"
pacman -Sy --quiet --noconfirm --needed gnupg archlinux-keyring

ALARM_KEY=68B3537F39A313B3E574D06777193F152BDBE6A6  # Arch Linux ARM Build System
log_debug "Using ALARM build key: ${ALARM_KEY}"

log_info "Initializing pacman-key keyring"
pacman-key --init

# Fetch ALARM key from primary keyserver
log_info "Fetching ALARM key from keyserver.ubuntu.com"
if ! pacman-key --recv-keys --keyserver hkps://keyserver.ubuntu.com "$ALARM_KEY"; then
    log_warn "Primary keyserver failed, retrying with keys.openpgp.org"
    pacman-key --recv-keys --keyserver hkps://keys.openpgp.org "$ALARM_KEY" \
        || die "Unable to retrieve ALARM signing key"
fi

log_info "Verifying ALARM key fingerprint"
pacman-key --finger "$ALARM_KEY" | sed -n '2p' || die "ALARM key fingerprint verification failed"

log_info "Locally trusting ALARM build key"
pacman-key --lsign-key "$ALARM_KEY" || die "Failed to locally trust ALARM key"

# Host emulation for ARM chroots
log_info "Installing qemu user emulator (qemu-user-static + binfmt)"
pacman -S --quiet --noconfirm --needed qemu-user-static qemu-user-static-binfmt
#pacman -Sy --quiet --noconfirm --needed qemu-user-static qemu-user-static-binfmt

# Host: mirrorlist for ALARM
log_info "Writing ALARM mirrorlist to /etc/pacman.d/arm-mirrorlist"
install -D -m0644 /dev/null /etc/pacman.d/arm-mirrorlist
cat >/etc/pacman.d/arm-mirrorlist <<'EOF'
Server = http://fl.us.mirror.archlinuxarm.org/$arch/$repo
EOF

# Host: ARM pacman conf
log_info "Generating /tmp/pacman.arm.conf"
cat >/tmp/pacman.arm.conf << EOF
[options]
Architecture = aarch64
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional
[core]
Include = /etc/pacman.d/arm-mirrorlist
[extra]
Include = /etc/pacman.d/arm-mirrorlist
[alarm]
Include = /etc/pacman.d/arm-mirrorlist
EOF

# Optional sanity check probe
log_info "Performing pacman ARM config sanity probe"
rm -rf /tmp/pdb && install -d /tmp/pdb


log_debug "Running pacman -Sy against temporary dbpath"
pacman -Sy --config /tmp/pacman.arm.conf --dbpath /tmp/pdb --noconfirm \
    || die "Pacman sync failed using ARM config"

log_debug "Running pacman -Sp (base) using temporary dbpath"
pacman -Sp base --config /tmp/pacman.arm.conf --dbpath /tmp/pdb >/dev/null \
    || die "Pacman package probe failed using ARM config"

log_info "Stage 30: host preparation complete"
