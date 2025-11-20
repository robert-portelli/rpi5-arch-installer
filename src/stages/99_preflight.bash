# Preflight Checklist
log_info "Stage 99: preflight check – verifying boot readiness"

fails=0

# Required boot files on ESP
req_files=(
    "${config[ESP_MNT]}/config.txt"
    "${config[ESP_MNT]}/cmdline.txt"
    "${config[ESP_MNT]}/bcm2712-rpi-5-b.dtb"
)

for f in "${req_files[@]}"; do
    if [[ ! -s "$f" ]]; then
        log_error "MISS: required boot file '$f'"
        ((fails++))
    fi
done

# Kernel presence
if [[ ! -s "${config[ESP_MNT]}/Image" && ! -s "${config[ESP_MNT]}/kernel8.img" ]]; then
    log_error "MISS: kernel (Image or kernel8.img) on ESP"
    ((fails++))
fi

[[ -s "${config[ESP_MNT]}/start4.elf" ]] || { log_error "MISS: start4.elf";   ((fails++)); }
[[ -s "${config[ESP_MNT]}/fixup4.dat" ]] || { log_error "MISS: fixup4.dat";   ((fails++)); }
[[ -d "${config[ESP_MNT]}/overlays" ]]  || { log_error "MISS: overlays/ dir"; ((fails++)); }

# initramfs followkernel (warning only)
if ! grep -q "^initramfs .* followkernel" "${config[ESP_MNT]}/config.txt"; then
    log_warn "WARN: initramfs followkernel not set in config.txt"
fi

# Ensure fstab exists
if [[ ! -s "${config[ROOT_MNT]}/etc/fstab" ]]; then
    log_info "fstab missing; generating via genfstab -U ${config[ROOT_MNT]}"
    genfstab -U "${config[ROOT_MNT]}" >> "${config[ROOT_MNT]}/etc/fstab"
fi

# Accept any / entry: UUID=, PARTUUID=, /dev/..., /dev/disk/by-...
if ! grep -Eq '^[[:space:]]*(UUID=|PARTUUID=|/dev/)[^[:space:]]+[[:space:]]+/[[:space:]]' \
    "${config[ROOT_MNT]}/etc/fstab"; then
    log_error "MISS: could not find root filesystem entry for '/' in fstab"
    ((fails++))
fi

# Optional: check ESP filesystem entry in fstab (if you expect it there)
# ESP_FS_UUID="$(blkid -s UUID -o value "/dev/disk/by-partuuid/${config[ESP_UUID]}")"
# if ! grep -Eq "^\s*UUID=${ESP_FS_UUID}\s+/boot\b" "${config[ROOT_MNT]}/etc/fstab"; then
#     log_warn "WARN: ESP filesystem UUID=${ESP_FS_UUID} not found for /boot in fstab"
# fi

# Architecture checks
if ! arch-chroot "${config[ROOT_MNT]}" pacman-conf Architecture | grep -qx aarch64; then
    log_error "MISS: pacman Architecture != aarch64 inside target"
    ((fails++))
fi

if ! arch-chroot "${config[ROOT_MNT]}" file -Lb /bin/bash | grep -q aarch64; then
    log_error "MISS: /bin/bash is not aarch64 inside target"
    ((fails++))
fi

# Ensure initramfs exists next to kernel inside ESP
if [[ ! -s "${config[ESP_MNT]}/initramfs-linux.img" ]]; then
    log_info "initramfs-linux.img not found on ESP; probing ${config[ROOT_MNT]}/boot"
    if [[ -s "${config[ROOT_MNT]}/boot/initramfs-linux.img" ]]; then
        cp -f "${config[ROOT_MNT]}/boot/initramfs-linux.img" "${config[ESP_MNT]}/" \
            || { log_error "MISS: failed to copy initramfs-linux.img to ESP"; ((fails++)); }
    fi
fi

if [[ ! -s "${config[ESP_MNT]}/initramfs-linux.img" ]]; then
    log_error "MISS: initramfs-linux.img in ESP"
    ((fails++))
fi

# Preflight verdict
if (( fails == 0 )); then
    log_info "Preflight verdict: Likely to boot, assuming EEPROM BOOT_ORDER allows NVMe and HAT power is adequate."
else
    log_error "Preflight verdict: Not ready (${fails} problems)."
    exit 1
fi
