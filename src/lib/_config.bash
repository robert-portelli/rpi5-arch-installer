# shellcheck shell=bash

# shellcheck disable=SC2034
declare -gA config=(
    [DISK]="__none__"
    [HOSTNAME]="rpi5-arch"
    [LOCALE]="en_US.UTF-8"
    [KEYMAP]="us"
    [TZ]="UTC"
    [ESP_UUID]=$(uuidgen --random)
    [ROOT_UUID]=$(uuidgen --random)
    [ESP_MNT]="/mnt/boot"
    [ROOT_MNT]="/mnt"
    [EMPTY]="force"   # force|require|refuse
    [LOG_LEVEL]="INFO"  # DEBUG|INFO|WARN|ERROR|QUIET
    [LOG_COLOR]=auto    # auto|always|never
    [LOG_TAG]="${0##*/}"
)

# ---------------------------------------------------------------------------
# Static network configuration
#
# Adjust these values to match your LAN. They are baked into the image.
# Example below:
#   Address:  10.0.0.50/24
#   Gateway:  10.0.0.1
#   DNS:      1.1.1.1, 9.9.9.9
# ---------------------------------------------------------------------------
config[IPA_TYPE]="DHCP"   #STATIC|DHCP
config[IFACE]="end0"
config[IPV4]="10.0.0.50"
config[NET_PREFIX]="24"
config[GATEWAY]="10.0.0.1"
config[DNS1]="1.1.1.1"
config[DNS2]="9.9.9.9"

# ---------------------------------------------------------------------------
# Sanity Checks
[[ -n "${config[ESP_UUID]}" ]] || { echo "ERROR: ESP UUID gen fail" >&2; exit 1; }
[[ -n "${config[ROOT_UUID]}" ]] || { echo "ERROR: ROOT UUID gen fail" >&2; exit 1; }
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# ZRAM swap via zram-generator (Optional)
# ---------------------------------------------------------------------------
config[ZRAM_SWAP_ENABLE]=1          # 1|0
