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
