# 'config' is provided by src/lib/_config.bash sourced in main.bash.
# shellcheck disable=SC2154

log_info "Stage 50: configure Raspberry Pi 5 boot assets on ${config[ESP_MNT]}"

# Save a copy of the vendor config.txt
log_debug "Checking for vendor config.txt at ${config[ESP_MNT]}/config.txt"
if [ ! -f "${config[ESP_MNT]}/config.txt" ]; then
    die "ERROR: ${config[ESP_MNT]} lacks vendor config.txt"
else
    log_info "Backing up vendor config.txt to bak_vendor_config.txt"
    cp -a -- "${config[ESP_MNT]}/config.txt" \
        "${config[ESP_MNT]}/bak_vendor_config.txt" \
        || die "Failed to back up vendor config.txt"
fi

# Overwrite vendor config.txt with settings for headless server
log_info "Determining kernel image name from target /boot"
KERNEL_NAME=$(
    arch-chroot "${config[ROOT_MNT]}" bash -lc \
        'cd /boot 2>/dev/null; [ -f Image ] && echo Image || { [ -f kernel8.img ] && echo kernel8.img; }'
)
: "${KERNEL_NAME:=kernel8.img}"
log_debug "Using kernel image name: ${KERNEL_NAME}"

# this is the headless server we will build towards, here for documentation
log_debug "Writing future headless config to ${config[ESP_MNT]}/future_config.txt"
cat >"${config[ESP_MNT]}"/future_config.txt <<EOF
arm_64bit=1
kernel=$KERNEL_NAME
initramfs initramfs-linux.img followkernel

# headless trims
camera_auto_detect=0
display_auto_detect=0
disable_fw_kms_setup=1
# remove GPU stack if not using HDMI:
# dtoverlay=vc4-kms-v3d
# max_framebuffers=2

# optional disables
dtoverlay=disable-wifi
dtoverlay=disable-bt
disable_audio=1
dtparam=spi=off
dtparam=i2c_arm=off
dtparam=uart0=off

# only for some non-HAT+ PCIe adapters:
# dtparam=pciex1
# If you want serial console, set: enable_uart=1 and keep uart0 on.
EOF

# this is the config to prove boot and increment towards headless server
log_info "Writing boot-proving config to ${config[ESP_MNT]}/config.txt"
cat >"${config[ESP_MNT]}"/config.txt <<EOF
arm_64bit=1
kernel=$KERNEL_NAME
initramfs initramfs-linux.img followkernel

# headless trims
camera_auto_detect=0
display_auto_detect=1
disable_fw_kms_setup=0
# remove GPU stack if not using HDMI:
dtoverlay=vc4-kms-v3d
max_framebuffers=2

# optional disables
dtoverlay=disable-wifi
dtoverlay=disable-bt
disable_audio=1
dtparam=spi=off
dtparam=i2c_arm=off
dtparam=uart0=off

# only for some non-HAT+ PCIe adapters:
# dtparam=pciex1
# If you want serial console, set: enable_uart=1 and keep uart0 on.
EOF

# save a copy of the vendor cmdline.txt
log_debug "Checking for vendor cmdline.txt at ${config[ESP_MNT]}/cmdline.txt"
if [ ! -f "${config[ESP_MNT]}/cmdline.txt" ]; then
    die "ERROR: ${config[ESP_MNT]} lacks vendor cmdline.txt"
else
    log_info "Backing up vendor cmdline.txt to bak_vendor_cmdline.txt"
    cp -a -- "${config[ESP_MNT]}/cmdline.txt" \
        "${config[ESP_MNT]}/bak_vendor_cmdline.txt" \
        || die "Failed to back up vendor cmdline.txt"
fi

# Bootstrap cmdline
log_info "Writing bootstrap cmdline.txt with root PARTUUID ${config[ROOT_UUID]}"
cat >"${config[ESP_MNT]}"/cmdline.txt <<EOF
root=PARTUUID="${config[ROOT_UUID]}" rw rootwait rootfstype=btrfs console=tty1
EOF

log_info "Stage 50: Raspberry Pi 5 boot asset configuration complete"
