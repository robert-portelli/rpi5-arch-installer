#'config' is provided by src/lib/_config.bash sourced in main.bash.
# shellcheck disable=SC2154

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
