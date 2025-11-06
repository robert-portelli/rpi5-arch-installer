#!/usr/bin/env bash
set -u
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly BASE_DIR
# soothe the linter for the time being:
echo "$BASE_DIR"

main() {
    # Inputs
    : "${DISK:=/dev/<>}"        # override: DISK=/dev/sda ./installer.sh
    : "${HOSTNAME:=arch}"
    : "${LOCALE:=en_US.UTF-8}"
    : "${KEYMAP:=us}"
    : "${TZ:=UTC}"
    : "${ESP_UUID:=$(uuidgen --random)}"
    : "${ROOT_UUID:=$(uuidgen --random)}"
    : "${ESP_MNT:=/mnt/boot}"
    : "${ROOT_MNT:=/mnt}"
    : "${EMPTY:=require}"

    [ -b "$DISK" ] || { echo "ERROR: DISK '$DISK' not found" >&2; exit 1; }


    # Layout declarations
    rm -rf /run/repart.d
    install -d /run/repart.d

    cat >/run/repart.d/10-esp.conf <<EOF
[Partition]
Type=esp
Label=ESP
UUID=${ESP_UUID}
SizeMinBytes=1G
SizeMaxBytes=1G
Minimize=off
EOF

    cat >/run/repart.d/20-root.conf <<EOF
[Partition]
Type=root-arm64
Label=root
UUID=${ROOT_UUID}
Format=btrfs
EOF

    # Apply partitioning (idempotent)
    systemd-repart \
        --pretty=yes \
        --definitions=/run/repart.d \
        --dry-run=no \
        --empty="$EMPTY"\
        "$DISK"

    partprobe "$DISK"
    udevadm settle --exit-if-exists="/dev/disk/by-partuuid/$ESP_UUID"
    udevadm settle --exit-if-exists="/dev/disk/by-partuuid/$ROOT_UUID"

    # format the esp
    mkfs.vfat -F 32 -n ESP "/dev/disk/by-partuuid/$ESP_UUID"


    # Ensure root mountpoint exists on host
    install -d "$ROOT_MNT"

    # Mount root (by PARTUUID)
    if ! mountpoint -q "$ROOT_MNT"; then
        mount "/dev/disk/by-partuuid/$ROOT_UUID" "$ROOT_MNT" \
        || { echo "ERROR: ROOT UUID '$ROOT_UUID' not mounted to $ROOT_MNT" >&2; exit 1; }
    fi

    # Create ESP mountpoint inside the mounted root
    install -d "$ROOT_MNT/boot"

    # Mount ESP (by PARTUUID)
    if ! mountpoint -q "$ESP_MNT"; then
        mount "/dev/disk/by-partuuid/$ESP_UUID" "$ESP_MNT"\
        || { echo "ERROR: ESP UUID '$ESP_UUID' not mounted to $ROOT_MNT" >&2; exit 1; }
    fi

    # --- Import Arch Linux ARM builder key on the LIVE ISO (host pacman) ---
    pacman -Sy --quiet --noconfirm --needed gnupg archlinux-keyring

    ALARM_KEY=68B3537F39A313B3E574D06777193F152BDBE6A6  # Arch Linux ARM Build System

    pacman-key --init

    # fetch from a reliable HKPS keyserver (fallback included)
    pacman-key --recv-keys --keyserver hkps://keyserver.ubuntu.com "$ALARM_KEY" \
      || pacman-key --recv-keys --keyserver hkps://keys.openpgp.org "$ALARM_KEY"

    # verify and locally trust
    pacman-key --finger "$ALARM_KEY" | sed -n '2p'
    pacman-key --lsign-key "$ALARM_KEY"

    # Host emulation for ARM chroots
    # provides qemu-aarch64-static and binfmt rules
    pacman -S --quiet --noconfirm --needed qemu-user-static qemu-user-static-binfmt
    #pacman -Sy --quiet --noconfirm --needed qemu-user-static qemu-user-static-binfmt

    # Host: mirrorlist for ALARM
    install -D -m0644 /dev/null /etc/pacman.d/arm-mirrorlist
    cat >/etc/pacman.d/arm-mirrorlist <<'EOF'
Server = http://fl.us.mirror.archlinuxarm.org/$arch/$repo
EOF

    # Host: ARM pacman conf
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

    # Optional sanity check probe (keeps host db clean)
    rm -rf /tmp/pdb && install -d /tmp/pdb
    pacman -Sy --config /tmp/pacman.arm.conf --dbpath /tmp/pdb --noconfirm || exit 1
    pacman -Sp base --config /tmp/pacman.arm.conf --dbpath /tmp/pdb >/dev/null || exit 1

    # install to target (creates a new, empty keyring via -K)
    pacstrap -C /tmp/pacman.arm.conf -GMK "$ROOT_MNT" base archlinuxarm-keyring || exit 1

    # sanity check:
    arch-chroot "$ROOT_MNT" pacman-conf Architecture | grep -qx aarch64 || { echo "target pacman.conf not aarch64"; exit 1; }

    # Target: persist config
    install -D -m0644 /etc/pacman.d/arm-mirrorlist "$ROOT_MNT/etc/pacman.d/arm-mirrorlist"
    install -D -m0644 /tmp/pacman.arm.conf "$ROOT_MNT/etc/pacman.conf"

    # seed the keyring:
    arch-chroot "$ROOT_MNT" pacman-key --init
    arch-chroot "$ROOT_MNT" pacman-key --populate archlinuxarm

    # sanity checks
    arch-chroot "$ROOT_MNT" pacman-conf Architecture | grep -qx aarch64 \
      || { echo "ERROR: pacman Architecture != aarch64"; exit 1; }

    arch-chroot "$ROOT_MNT" file -Lb /bin/bash | grep -q aarch64 \
      || { echo "ERROR: /bin/bash is not aarch64"; exit 1; }

    # avoid creating the initramfs twice, install mkinitcpio and edit conf before kernel install
    # (once via kernel post install hook and once with edited mkinitcpio.conf)
    arch-chroot "$ROOT_MNT" pacman -S --quiet --noconfirm mkinitcpio

    # save a copy of the original mkinitcpio.conf
    if [ ! -f "$ROOT_MNT/etc/mkinitcpio.conf" ]; then
        { echo "ERROR: $ROOT_MNT/etc lacks mkinitcpio.conf"; exit 1; }
    else
        cp -a -- "$ROOT_MNT/etc/mkinitcpio.conf" "$ESP_MNT/bak_original_mkinitcpio.conf"
    fi

    # set a console font
    echo "KEYMAP=us" > "$ROOT_MNT/etc/vconsole.conf"

    # set the FILES in mkinitcpio.conf
    sed -i 's|^FILES=.*|FILES=(/etc/vconsole.conf)|' "$ROOT_MNT/etc/mkinitcpio.conf"

    # set the HOOKS in mkinitcpio.conf
    # this is for proving boot, later transition to headless hooks
    sed -i 's|^HOOKS=.*|HOOKS=(base udev autodetect modconf block filesystems)|' \
      "$ROOT_MNT/etc/mkinitcpio.conf"
    ## this is a documentation for the future headless HOOKS:
    ## HOOKS=(base udev autodetect modconf block filesystems)

    # Target: kernel + firmware
    # Note: Uses the target's pacman
    arch-chroot "$ROOT_MNT" pacman -S --quiet --noconfirm linux-rpi-16k rpi5-eeprom \
        firmware-raspberrypi btrfs-progs

    # --- Copy the emulator into target for chroot if host register qemu without F, or with a non-static interpreter, or with binfmt disabled
    # precheck: ensure emulator exists on host
    command -v /usr/bin/qemu-aarch64-static >/dev/null || {
      echo "qemu-aarch64-static missing"; exit 1
    }

    # probe; if chroot can't exec aarch64, inject emulator
    if ! chroot "$ROOT_MNT" /usr/bin/uname -m >/dev/null 2>&1; then
      install -D /usr/bin/qemu-aarch64-static "$ROOT_MNT/usr/bin/qemu-aarch64-static"
      # verify
      chroot "$ROOT_MNT" /usr/bin/uname -m | grep -qx aarch64 || {
        echo "aarch64 emulation still unavailable"; exit 1
      }
    fi
    # ---

    # Save a copy of the vendor config.txt
    if [ ! -f "$ESP_MNT/config.txt" ]; then
        { echo "ERROR: $ESP_MNT lacks vendor config.txt"; exit 1; }
    else
        cp -a -- "$ESP_MNT/config.txt" "$ESP_MNT/bak_vendor_config.txt"
    fi

    # Overwrite vendor config.txt with settings for headless server
    KERNEL_NAME=$(arch-chroot "$ROOT_MNT" bash -lc 'cd /boot 2>/dev/null; [ -f Image ] && echo Image || { [ -f kernel8.img ] && echo kernel8.img; }')
    : "${KERNEL_NAME:=kernel8.img}"

    # this is the headless server we will build towards, here for documentation
    cat >"$ESP_MNT"/future_config.txt <<EOF
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
    cat >"$ESP_MNT"/config.txt <<EOF
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
    if [ ! -f "$ESP_MNT/cmdline.txt" ]; then
        { echo "ERROR: $ESP_MNT lacks vendor cmdline.txt"; exit 1; }
    else
        cp -a -- "$ESP_MNT/cmdline.txt" "$ESP_MNT/bak_vendor_cmdline.txt"
    fi

    # Bootstrap cmdline
    cat >"$ESP_MNT"/cmdline.txt <<EOF
root=PARTUUID=$ROOT_UUID rw rootwait rootfstype=btrfs console=tty1
EOF

    # create the initramfs
    ## not needed since installing the kernel runs a post install hook to create initramfs
    #arch-chroot "$ROOT_MNT" mkinitcpio -P

    # First boot identity (idempotent defaults)
      #--root-password-locked \
    systemd-firstboot \
      --root="${ROOT_MNT}" \
      --locale="$LOCALE" \
      --keymap="$KEYMAP" \
      --timezone="$TZ" \
      --hostname="$HOSTNAME" \
      --setup-machine-id \
      --delete-root-password --force # for boot testing only

    # Finish
    sync
    echo "Converged. Re-run any time; unchanged targets are left intact."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    umount -R "$ROOT_MNT"
 fi
