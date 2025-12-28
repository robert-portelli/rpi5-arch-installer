#'config' is provided by src/lib/_config.bash sourced in main.bash.
# shellcheck disable=SC2154

log_info "Stage 30: host preparation (ALARM key, qemu, pacman config)"

# preserve the host's x86 mirrorlist (one-time snapshot)
if [[ -e /etc/pacman.d/x86_mirrorlist ]]; then
    log_debug "Host x86 mirrorlist already preserved at /etc/pacman.d/x86_mirrorlist; skipping copy"
elif [[ -e /etc/pacman.d/mirrorlist ]]; then
    log_debug "Preserving host x86 mirrorlist: /etc/pacman.d/mirrorlist -> /etc/pacman.d/x86_mirrorlist"
    cp /etc/pacman.d/mirrorlist /etc/pacman.d/x86_mirrorlist
else
    log_debug "Host x86 mirrorlist not found at /etc/pacman.d/mirrorlist; nothing to preserve"
fi

# point the host's x86 pacman conf to the preserved mirrorlist
# Point all repo Includes in pacman.conf at the new path
sed -i 's#/etc/pacman.d/mirrorlist#/etc/pacman.d/x86_mirrorlist#g' /etc/pacman.conf

# preserve the host's x86 pacman config
cp /etc/pacman.conf /etc/x86_pacman.conf

# prepare the host x86 pacman
pacman-key --config /etc/x86_pacman.conf --init
pacman-key --config /etc/x86_pacman.conf --populate archlinux

# Download and install x86 tools
pacman --config /etc/x86_pacman.conf -Sy --quiet --noconfirm --needed gnupg archlinux-keyring

# --- Import Arch Linux ARM builder key on the LIVE ISO (host pacman) ---
ALARM_KEY=68B3537F39A313B3E574D06777193F152BDBE6A6  # Arch Linux ARM Build System
log_debug "Using ALARM build key: ${ALARM_KEY}"

# Fetch ALARM key from primary keyserver
log_debug "Fetching ALARM key from keyserver.ubuntu.com"
if ! pacman-key --config /etc/x86_pacman.conf \
                --recv-keys \
                --keyserver hkps://keyserver.ubuntu.com "$ALARM_KEY"; then
    log_warn "Primary keyserver failed, retrying with keys.openpgp.org"
    pacman-key --config /etc/x86_pacman.conf \
                --recv-keys \
                --keyserver hkps://keys.openpgp.org "$ALARM_KEY" \
                || die "Unable to retrieve ALARM signing key"
fi

log_debug "Verifying ALARM key fingerprint"
pacman-key --config /etc/x86_pacman.conf --finger "$ALARM_KEY" | sed -n '2p' \
    || die "ALARM key fingerprint verification failed"

log_debug "Locally trusting ALARM build key"
pacman-key --config /etc/x86_pacman.conf --lsign-key "$ALARM_KEY" \
    || die "Failed to locally trust ALARM key"

# Host emulation for ARM chroots
log_debug "Installing qemu user emulator (qemu-user-static + binfmt)"
pacman --config /etc/x86_pacman.conf \
    -S --quiet --noconfirm --needed qemu-user-static qemu-user-static-binfmt
#pacman -Sy --quiet --noconfirm --needed qemu-user-static qemu-user-static-binfmt

# Host: mirrorlist for ALARM
log_debug "Clobbering host x86 mirrorlist with arm mirrorlist"
#install -D -m0644 /dev/null /etc/pacman.d/arm.mirrorlist
cat >/etc/pacman.d/mirrorlist <<'EOF'
Server = http://fl.us.mirror.archlinuxarm.org/$arch/$repo
EOF

# Host: ARM pacman conf
#log_info "Generating /tmp/pacman.arm.conf"
log_debug "Checking for host pacman config"

#pacman_conf="$BASE_DIR/src/assets/pacman/pacman.arm.conf.bootstrap"
#if [[ ! -f "$pacman_conf" ]]; then
#    die "The host and target require a specific pacman config"

# by persisting the x86 mirrorlist under a different name and then clobbering it,
# we facilitate the handoff the to eventual stock arm mirrorlist in the target
cat >/tmp/pacman.arm.conf.bootstrap << EOF
[options]
Architecture = aarch64
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional
Color
CheckSpace
ParallelDownloads = 8
[core]
Include = /etc/pacman.d/mirrorlist
[extra]
Include = /etc/pacman.d/mirrorlist
[alarm]
Include = /etc/pacman.d/mirrorlist
EOF

# Optional sanity check probe
log_debug "Performing pacman ARM config sanity probe"
rm -rf /tmp/pdb && install -d /tmp/pdb


log_debug "Running pacman -Sy against temporary dbpath"
pacman -Sy --config /tmp/pacman.arm.conf.bootstrap --dbpath /tmp/pdb --noconfirm \
    || die "Pacman sync failed using ARM config"

log_debug "Running pacman -Sp (base) using temporary dbpath"
pacman -Sp base --config /tmp/pacman.arm.conf.bootstrap --dbpath /tmp/pdb >/dev/null \
    || die "Pacman package probe failed using ARM config"

log_info "Stage 30: host preparation complete"
