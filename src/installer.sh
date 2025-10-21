#!/usr/bin/env bash
set -euo pipefail

# Inputs
: "${DISK:=/dev/sdb}"        # override: DISK=/dev/sda ./installer.sh
: "${HOSTNAME:=arch}"
: "${LOCALE:=en_US.UTF-8}"
: "${KEYMAP:=us}"
: "${TZ:=UTC}"
: "${ESP_UUID:=$(uuidgen --random)}"
: "${ROOT_UUID:=$(uuidgen --random)}"
: "${ESP_MNT:=/mnt/boot}"
: "${ROOT_MNT:=/mnt}"

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
    --empty=force\
    "$DISK"

udevadm settle --exit-if-exists="/dev/disk/by-partuuid/$ESP_UUID"
udevadm settle --exit-if-exists="/dev/disk/by-partuuid/$ROOT_UUID"

# format the esp
mkfs.vfat -F 32 -n ESP "/dev/disk/by-partuuid/$ESP_UUID"


# Ensure root mountpoint exists on host
install -d -v -m 0755 -o root -g root "$ROOT_MNT"

# Mount root (by PARTUUID)
mountpoint -q "$ROOT_MNT" || mount "/dev/disk/by-partuuid/$ROOT_UUID" "$ROOT_MNT"

# Create ESP mountpoint inside the mounted root
install -d -v -m 0755 -o root -g root "$ROOT_MNT/boot"

# Mount ESP (by PARTUUID)
mountpoint -q "$ESP_MNT" || mount "/dev/disk/by-partuuid/$ESP_UUID" "$ESP_MNT"

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
# ---

# --- Host: mirrorlist and conf for ALARM
#install -D -m0644 /dev/null /etc/pacman.d/arm-mirrorlist
#install -D -T -v -m 0644 -o root -g root /dev/null /etc/pacman.d/arm-mirrorlist
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
# ---

# Optional sanity check probe (keeps host db clean)
rm -rf /tmp/pdb && install -d /tmp/pdb
pacman -Sy --config /tmp/pacman.arm.conf --dbpath /tmp/pdb --noconfirm || exit 1
pacman -Sp base --config /tmp/pacman.arm.conf --dbpath /tmp/pdb >/dev/null || exit 1

# install to target (creates a new, empty keyring via -K)
pacstrap -C /tmp/pacman.arm.conf -GMK "$ROOT_MNT" base archlinuxarm-keyring || exit 1

# sanity check:
arch-chroot "$ROOT_MNT" pacman-conf Architecture | grep -qx aarch64 || { echo "target pacman.conf not aarch64"; exit 1; }

# Target: persist config
install -D -T -v -m 0644 -o root -g root /etc/pacman.d/arm-mirrorlist "$ROOT_MNT/etc/pacman.d/arm-mirrorlist"
install -D -T -v -m 0644 -o root -g root /tmp/pacman.arm.conf "$ROOT_MNT/etc/pacman.conf"

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

# Host: generate the target's fstab
genfstab -U "$ROOT_MNT" > "$ROOT_MNT/etc/fstab"

####### level 2
arch-chroot "$MNT_ROOT" /usr/bin/env bash -eux <<'EOF'
pacman -S --noconfirm ufw

# enable sshd; ufw will be applied at next boot
systemctl enable sshd ufw.service

# define ufw policy and rules; safe even while ufw is disabled
ufw default deny incoming
ufw default allow outgoing
ufw limit ssh
ufw enable
EOF

# Finish
sync
echo "Converged. Re-run any time; unchanged targets are left intact."

# Preflight Checklist
echo "[Preflight] Checking boot readiness…"

fails=0
req_files=(
  "$ESP_MNT/config.txt"
  "$ESP_MNT/cmdline.txt"
  "$ESP_MNT/bcm2712-rpi-5-b.dtb"
)
for f in "${req_files[@]}"; do
  [[ -s "$f" ]] || { echo "MISS: $f"; ((fails++)); }
done

[[ -s "$ESP_MNT/Image" || -s "$ESP_MNT/kernel8.img" ]] || { echo "MISS: kernel (Image or kernel8.img)"; ((fails++)); }
[ -s "$ESP_MNT/start4.elf" ]   || { echo "MISS: start4.elf";   ((fails++)); }
[ -s "$ESP_MNT/fixup4.dat" ]   || { echo "MISS: fixup4.dat";   ((fails++)); }
[ -d "$ESP_MNT/overlays" ]     || { echo "MISS: overlays/";    ((fails++)); }

grep -q "^initramfs .* followkernel" "$ESP_MNT/config.txt" || { echo "WARN: initramfs followkernel not set"; }
ROOT_FS_UUID="$(blkid -s UUID -o value "/dev/disk/by-partuuid/$ROOT_UUID")"
grep -Eq "^\s*UUID=${ROOT_FS_UUID}\s+/\s" "$ROOT_MNT/etc/fstab" \
  || { echo "MISS: root filesystem UUID in fstab"; ((fails++)); }


arch-chroot "$ROOT_MNT" pacman-conf Architecture | grep -qx aarch64 || { echo "MISS: pacman arch!=aarch64"; ((fails++)); }
arch-chroot "$ROOT_MNT" file -Lb /bin/bash | grep -q aarch64 || { echo "MISS: /bin/bash not aarch64"; ((fails++)); }

# Ensure initramfs exists next to kernel inside target
[[ -s "$ESP_MNT/initramfs-linux.img" ]] || {
  # some builds place it under /boot first; copy if needed
  [[ -s "$ROOT_MNT/boot/initramfs-linux.img" ]] && cp -f "$ROOT_MNT/boot/initramfs-linux.img" "$ESP_MNT/"
}
[[ -s "$ESP_MNT/initramfs-linux.img" ]] || { echo "MISS: initramfs-linux.img in ESP"; ((fails++)); }

# Generate fstab if missing and verify PARTUUIDs
[[ -s "$ROOT_MNT/etc/fstab" ]] || genfstab -U "$ROOT_MNT" >> "$ROOT_MNT/etc/fstab"
grep -q "$ROOT_UUID" "$ROOT_MNT/etc/fstab" || { echo "MISS: ROOT PARTUUID in fstab"; ((fails++)); }
grep -q "$ESP_UUID"  "$ROOT_MNT/etc/fstab" || { echo "MISS: ESP PARTUUID in fstab";  ((fails++)); }

if ((fails==0)); then
  echo "Preflight verdict: Likely to boot, assuming EEPROM BOOT_ORDER allows NVMe and NVMe HAT power is adequate."
else
  echo "Preflight verdict: Not ready ($fails problems)."
  exit 1
fi
