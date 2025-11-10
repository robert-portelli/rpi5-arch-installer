# 'config' is provided by src/lib/_config.bash sourced in main.bash.
# shellcheck disable=SC2154

# install to target (creates a new, empty keyring via -K)
pacstrap -C /tmp/pacman.arm.conf -GMK "${config[ROOT_MNT]}" base archlinuxarm-keyring || exit 1

# sanity check:
arch-chroot "${config[ROOT_MNT]}" pacman-conf Architecture | grep -qx aarch64 || { echo "target pacman.conf not aarch64"; exit 1; }

# Target: persist config
install -D -m0644 /etc/pacman.d/arm-mirrorlist "${config[ROOT_MNT]}/etc/pacman.d/arm-mirrorlist"
install -D -m0644 /tmp/pacman.arm.conf "${config[ROOT_MNT]}/etc/pacman.conf"

# seed the keyring:
arch-chroot "${config[ROOT_MNT]}" pacman-key --init
arch-chroot "${config[ROOT_MNT]}" pacman-key --populate archlinuxarm

# sanity checks
arch-chroot "${config[ROOT_MNT]}" pacman-conf Architecture | grep -qx aarch64 \
  || { echo "ERROR: pacman Architecture != aarch64"; exit 1; }

arch-chroot "${config[ROOT_MNT]}" file -Lb /bin/bash | grep -q aarch64 \
  || { echo "ERROR: /bin/bash is not aarch64"; exit 1; }

# avoid creating the initramfs twice, install mkinitcpio and edit conf before kernel install
# (once via kernel post install hook and once with edited mkinitcpio.conf)
arch-chroot "${config[ROOT_MNT]}" pacman -S --quiet --noconfirm mkinitcpio

# save a copy of the original mkinitcpio.conf
if [ ! -f "${config[ROOT_MNT]}/etc/mkinitcpio.conf" ]; then
    { echo "ERROR: ${config[ROOT_MNT]}/etc lacks mkinitcpio.conf"; exit 1; }
else
    cp -a -- "${config[ROOT_MNT]}/etc/mkinitcpio.conf" "${config[ESP_MNT]}/bak_original_mkinitcpio.conf"
fi

# set a console font
echo "KEYMAP=us" > "${config[ROOT_MNT]}/etc/vconsole.conf"

# set the FILES in mkinitcpio.conf
sed -i 's|^FILES=.*|FILES=(/etc/vconsole.conf)|' "${config[ROOT_MNT]}/etc/mkinitcpio.conf"

# set the HOOKS in mkinitcpio.conf
# this is for proving boot, later transition to headless hooks
sed -i 's|^HOOKS=.*|HOOKS=(base udev autodetect modconf block filesystems)|' \
  "${config[ROOT_MNT]}/etc/mkinitcpio.conf"
## this is a documentation for the future headless HOOKS:
## HOOKS=(base udev autodetect modconf block filesystems)

# Target: kernel + firmware
# Note: Uses the target's pacman
arch-chroot "${config[ROOT_MNT]}" pacman -S --quiet --noconfirm linux-rpi-16k rpi5-eeprom \
    firmware-raspberrypi btrfs-progs

# --- Copy the emulator into target for chroot if host register qemu without F, or with a non-static interpreter, or with binfmt disabled
# precheck: ensure emulator exists on host
command -v /usr/bin/qemu-aarch64-static >/dev/null || {
  echo "qemu-aarch64-static missing"; exit 1
}

# probe; if chroot can't exec aarch64, inject emulator
if ! chroot "${config[ROOT_MNT]}" /usr/bin/uname -m >/dev/null 2>&1; then
  install -D /usr/bin/qemu-aarch64-static "${config[ROOT_MNT]}/usr/bin/qemu-aarch64-static"
  # verify
  chroot "${config[ROOT_MNT]}" /usr/bin/uname -m | grep -qx aarch64 || {
    echo "aarch64 emulation still unavailable"; exit 1
  }
fi
# ---
