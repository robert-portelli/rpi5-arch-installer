# src/lib/_logger.bash
# shellcheck shell=bash

# Lazy init guard: 0 or unset = not initialized, 1 = initialized
# Do not export; this is just a shell variable.
# LOGGER_INITIALIZED is intentionally left unset here.

_logger_init() {
    # Fast path: if already initialized, return immediately
    if [[ ${LOGGER_INITIALIZED:-0} -eq 1 ]]; then
        return 0
    fi

    # Ensure config exists; respect an existing one from _config.bash
    if ! declare -p config &>/dev/null; then
        declare -gA config=(
            [LOG_LEVEL]=INFO
            [LOG_COLOR]=auto
            [LOG_TAG]="${0##*/}"
        )
    fi

    # Our internal maps: we own these, so just define them once
    declare -gA LOG_LEVELS=(
        [DEBUG]=0
        [INFO]=1
        [WARN]=2
        [ERROR]=3
        [QUIET]=4
    )

    declare -gA LOG_COLORS=(
        [DEBUG]=$'\033[2m'
        [INFO]=''
        [WARN]=$'\033[33m'
        [ERROR]=$'\033[31m'
    )

    # Global reset sequence for colored output
    declare -g LOGGER_RESET=$'\033[0m'

    LOGGER_INITIALIZED=1
}

_logger_use_color() {
    case "${config[LOG_COLOR]}" in
        always) return 0 ;;
        never)  return 1 ;;
        auto)
            [ -t 2 ] || return 1
            return 0
            ;;
        *)
            [ -t 2 ] || return 1
            return 0
            ;;
    esac
}

_logger_log() {
    _logger_init    # lazy-init: first call does all the work

    local level="$1"
    shift || true

    # Filter
    if (( LOG_LEVELS[$level] < LOG_LEVELS[${config[LOG_LEVEL]}] )); then
        return 0
    fi

    local ts color reset msg tag fmt
    ts="$(date +'%Y-%m-%dT%H:%M:%S%z')"
    tag="${config[LOG_TAG]}"

    # Treat the next argument as a printf-style format string, rest as args
    fmt=${1-}
    shift || true

    if [[ -n $fmt ]]; then
        # Build the formatted message into msg
        # shellcheck disable=SC2059  # fmt is intentionally used as a format string
        printf -v msg "$fmt" "$@"
    else
        msg=""
    fi

    if _logger_use_color; then
        color="${LOG_COLORS[$level]}"
        reset="$LOGGER_RESET"
    else
        color=''
        reset=''
    fi

    if [[ -n $color ]]; then
        # color and reset are %b so escape sequences are interpreted
        printf '%s [%s] %s: %b%s%b\n' \
            "$ts" "$level" "$tag" \
            "$color" "$msg" "$reset" >&2
    else
        printf '%s [%s] %s: %s\n' \
            "$ts" "$level" "$tag" "$msg" >&2
    fi
}

log_debug() { _logger_log DEBUG "$@"; }
log_info()  { _logger_log INFO  "$@"; }
log_warn()  { _logger_log WARN  "$@"; }
log_error() { _logger_log ERROR "$@"; }

die() {
    _logger_log ERROR "$@"
    exit 1
}
