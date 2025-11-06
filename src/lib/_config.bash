# shellcheck shell=bash

# shellcheck disable=SC2034
declare -gA config=(
    [DISK]="/dev/sdb"
    [HOSTNAME]="rpi5-arch"
    [LOCALE]="en_US.UTF-8"
    [KEYMAP]="us"
    [TZ]="UTC"
    [ESP_UUID]=$(uuidgen --random)
    [ROOT_UUID]=$(uuidgen --random)
    [ESP_MNT]="/mnt/boot"
    [ROOT_MNT]="/mnt"
    [EMPTY]="force"   # force|require|refuse
)

[[ -b "${config[DISK]}" ]] || { echo "ERROR: DISK ${config[DISK]} not found" >&2; exit 1; }
[[ -n "${config[ESP_UUID]}" ]] || { echo "ERROR: ESP UUID gen fail" >&2; exit 1; }
[[ -n "${config[ROOT_UUID]}" ]] || { echo "ERROR: ROOT UUID gen fail" >&2; exit 1; }
