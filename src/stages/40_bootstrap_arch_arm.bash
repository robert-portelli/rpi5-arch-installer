# 'config' is provided by src/lib/_config.bash sourced in main.bash.
# shellcheck disable=SC2154

log_info "Stage 40: bootstrap Arch Linux ARM into ${config[ROOT_MNT]}"

# install to target (creates a new, empty keyring via -K)
log_debug "Running pacstrap into ${config[ROOT_MNT]} with ARM config /tmp/pacman.arm.conf"
pacstrap -C /tmp/pacman.arm.conf.bootstrap -GMK "${config[ROOT_MNT]}" \
    base \
    archlinuxarm-keyring \
    iptables-nft \
    nftables \
    || die "pacstrap failed for target ${config[ROOT_MNT]}"

# check for the alpm download user
if arch-chroot "${config[ROOT_MNT]}" bash -c 'id -u alpm >/dev/null 2>&1'; then
    log_debug "User alpm exists in target"
else
    die "DownloadUser=alpm is set but user alpm does not exist in target"
fi

# sanity check:
log_debug "Verifying target pacman Architecture is aarch64"
arch-chroot "${config[ROOT_MNT]}" pacman-conf Architecture | grep -qx aarch64 \
    || die "target pacman.conf Architecture is not aarch64"

# pacman mirrorlist
log_debug "Backing up stock target mirrorlist (one-time snapshot)"
if [[ -e "${config[ROOT_MNT]}/etc/pacman.d/mirrorlist.orig" ]]; then
    log_debug "Target /etc/pacman.d/mirrorlist.orig already exists; skipping backup"
else
    cp -a -- "${config[ROOT_MNT]}/etc/pacman.d/mirrorlist" "${config[ROOT_MNT]}/etc/pacman.d/mirrorlist.orig" \
        || log_error "Failed to back up target pacman mirror list"
fi

log_debug "Clobbering the target's mirrorlist with the host's ALARM mirrorlist"
install -D -m0644 /etc/pacman.d/mirrorlist "${config[ROOT_MNT]}/etc/pacman.d/mirrorlist"


# pacman config
install -D -m0644 /tmp/pacman.arm.conf.bootstrap "${config[ROOT_MNT]}/etc/pacman.arm.conf.bootstrap"
log_debug "Backing up stock target /etc/pacman.conf (one-time snapshot)"
if [[ -e "${config[ROOT_MNT]}/etc/pacman.conf.orig" ]]; then
    log_debug "Target /etc/pacman.conf.orig already exists; skipping backup"
else
    cp -a -- "${config[ROOT_MNT]}/etc/pacman.conf" "${config[ROOT_MNT]}/etc/pacman.conf.orig" \
        || log_error "Failed to back up target pacman.conf"
fi

log_debug "Enabling pacman Color in target"
sed -i 's/^[[:space:]]*#\?[[:space:]]*Color[[:space:]]*$/Color/' \
    "${config[ROOT_MNT]}/etc/pacman.conf"

log_debug "Setting pacman ParallelDownloads=8 in target"
if grep -qE '^[[:space:]]*#?[[:space:]]*ParallelDownloads[[:space:]]*=' \
    "${config[ROOT_MNT]}/etc/pacman.conf"; then
    sed -i 's/^[[:space:]]*#\?[[:space:]]*ParallelDownloads[[:space:]]*=.*/ParallelDownloads = 8/' \
        "${config[ROOT_MNT]}/etc/pacman.conf"
else
    printf '\nParallelDownloads = 8\n' >> "${config[ROOT_MNT]}/etc/pacman.conf"
fi


# seed the keyring:
log_debug "Initializing and populating pacman keyring inside target"
arch-chroot "${config[ROOT_MNT]}" pacman-key --init \
    || die "pacman-key --init failed inside target"
arch-chroot "${config[ROOT_MNT]}" pacman-key --populate archlinuxarm \
    || die "pacman-key --populate archlinuxarm failed inside target"

# sanity checks
log_debug "Re-verifying pacman Architecture and /bin/bash ABI in target"
arch-chroot "${config[ROOT_MNT]}" pacman-conf Architecture | grep -qx aarch64 \
    || die "ERROR: pacman Architecture != aarch64"

arch-chroot "${config[ROOT_MNT]}" file -Lb /bin/bash | grep -q aarch64 \
    || die "ERROR: /bin/bash is not aarch64"

log_debug "Sanity check: pacman in target can resolve base from default repos"
arch-chroot "${config[ROOT_MNT]}" bash -c 'pacman --config /etc/pacman.arm.conf.bootstrap -Sp base >/dev/null' \
    || die "Target pacman could not resolve base package from configured repos"

# avoid creating the initramfs twice, install mkinitcpio and edit conf before kernel install
# (once via kernel post install hook and once with edited mkinitcpio.conf)
log_debug "Installing mkinitcpio in target"
arch-chroot "${config[ROOT_MNT]}" pacman --config /etc/pacman.arm.conf.bootstrap -S --quiet --noconfirm mkinitcpio \
    || die "Failed to install mkinitcpio in target"

# save a copy of the original mkinitcpio.conf
log_debug "Checking for mkinitcpio.conf in target and backing up original to ESP"
if [ ! -f "${config[ROOT_MNT]}/etc/mkinitcpio.conf" ]; then
    die "ERROR: ${config[ROOT_MNT]}/etc lacks mkinitcpio.conf"
else
    cp -a -- "${config[ROOT_MNT]}/etc/mkinitcpio.conf" \
        "${config[ESP_MNT]}/bak_original_mkinitcpio.conf" \
        || die "Failed to back up mkinitcpio.conf to ${config[ESP_MNT]}"
fi

# set a console font
log_debug "Writing vconsole KEYMAP=us into target"
echo "KEYMAP=us" > "${config[ROOT_MNT]}/etc/vconsole.conf"

# set the FILES in mkinitcpio.conf
log_debug "Setting FILES in mkinitcpio.conf to include /etc/vconsole.conf"
sed -i 's|^FILES=.*|FILES=(/etc/vconsole.conf)|' \
    "${config[ROOT_MNT]}/etc/mkinitcpio.conf"

# set the HOOKS in mkinitcpio.conf
# this is for proving boot, later transition to headless hooks
log_debug "Setting HOOKS in mkinitcpio.conf for interactive proof-of-boot"
sed -i 's|^HOOKS=.*|HOOKS=(base udev autodetect modconf block filesystems)|' \
    "${config[ROOT_MNT]}/etc/mkinitcpio.conf"
## this is documentation for the future headless HOOKS:
## HOOKS=(base udev autodetect modconf block filesystems)

# Target: kernel + firmware
# Note: Uses the target's pacman
log_debug "Installing kernel, EEPROM tools, firmware, and btrfs-progs into target"
arch-chroot "${config[ROOT_MNT]}" pacman --config /etc/pacman.arm.conf.bootstrap -S --quiet --noconfirm \
    linux-rpi-16k rpi5-eeprom firmware-raspberrypi btrfs-progs util-linux\
    || die "Failed to install kernel/firmware packages in target"

# --- Copy the emulator into target for chroot if host registered qemu without F,
# or with a non-static interpreter, or with binfmt disabled

# precheck: ensure emulator exists on host
log_debug "Verifying qemu-aarch64-static exists on host"
command -v /usr/bin/qemu-aarch64-static >/dev/null \
    || die "qemu-aarch64-static missing on host"

# probe; if chroot can't exec aarch64, inject emulator
log_debug "Probing aarch64 execution inside chroot"
if ! chroot "${config[ROOT_MNT]}" /usr/bin/uname -m >/dev/null 2>&1; then
    log_warn "Target chroot cannot execute aarch64; copying qemu-aarch64-static into target"
    install -D /usr/bin/qemu-aarch64-static \
        "${config[ROOT_MNT]}/usr/bin/qemu-aarch64-static" \
        || die "Failed to copy qemu-aarch64-static into target"

    # verify
    chroot "${config[ROOT_MNT]}" /usr/bin/uname -m | grep -qx aarch64 \
        || die "aarch64 emulation still unavailable in target after injecting qemu-aarch64-static"
else
    log_debug "aarch64 execution inside chroot is already functional"
fi
# ---

log_info "Stage 40: bootstrap Arch Linux ARM complete"
