# 'config' is provided by src/lib/_config.bash sourced in main.bash.
# shellcheck disable=SC2154

# Save a copy of the vendor config.txt
if [ ! -f "${config[ESP_MNT]}/config.txt" ]; then
    { echo "ERROR: ${config[ESP_MNT]} lacks vendor config.txt"; exit 1; }
else
    cp -a -- "${config[ESP_MNT]}/config.txt" "${config[ESP_MNT]}/bak_vendor_config.txt"
fi

# Overwrite vendor config.txt with settings for headless server
KERNEL_NAME=$(arch-chroot "${config[ROOT_MNT]}" bash -lc 'cd /boot 2>/dev/null; [ -f Image ] && echo Image || { [ -f kernel8.img ] && echo kernel8.img; }')
: "${KERNEL_NAME:=kernel8.img}"

# this is the headless server we will build towards, here for documentation
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
if [ ! -f "${config[ESP_MNT]}/cmdline.txt" ]; then
    { echo "ERROR: ${config[ESP_MNT]} lacks vendor cmdline.txt"; exit 1; }
else
    cp -a -- "${config[ESP_MNT]}/cmdline.txt" "${config[ESP_MNT]}/bak_vendor_cmdline.txt"
fi

# Bootstrap cmdline
cat >"${config[ESP_MNT]}"/cmdline.txt <<EOF
root=PARTUUID="${config[ROOT_UUID]}" rw rootwait rootfstype=btrfs console=tty1
EOF
