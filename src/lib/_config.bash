# shellcheck shell=bash
: "${DISK:=/dev/<>}"        # override: DISK=/dev/sda ./installer.sh
: "${HOSTNAME:=arch}"
: "${LOCALE:=en_US.UTF-8}"
: "${KEYMAP:=us}"
: "${TZ:=UTC}"
: "${ESP_UUID:=$(uuidgen --random)}"
: "${ROOT_UUID:=$(uuidgen --random)}"
: "${ESP_MNT:=/mnt/boot}"
: "${ROOT_MNT:=/mnt}"
: "${EMPTY:=require}"  # force|require|refuse

[[ -b $DISK ]] || { echo "ERROR: DISK '$DISK' not found" >&2; exit 1; }
[[ -n $ESP_UUID ]] || { echo "ERROR: ESP UUID gen fail" >&2; exit 1; }
[[ -n $ROOT_UUID ]] || { echo "ERROR: ROOT UUID gen fail" >&2; exit 1; }
