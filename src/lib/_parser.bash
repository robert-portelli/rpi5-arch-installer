# src/lib/_parser.bash
# shellcheck shell=bash

_usage_message() {
    cat <<EOF
Usage: ${0##*/} [OPTIONS]

Options:
  -d, --disk PATH          Target disk (e.g. /dev/sda)
      --hostname NAME      Hostname (default: ${config[HOSTNAME]})
      --locale LOCALE      Locale (default: ${config[LOCALE]})
      --keymap MAP         Console keymap (default: ${config[KEYMAP]})
      --tz ZONE            Timezone (default: ${config[TZ]})
      --esp-uuid UUID      ESP partition PARTUUID
      --root-uuid UUID     Root partition PARTUUID
      --esp-mnt PATH       ESP mountpoint (default: ${config[ESP_MNT]})
      --root-mnt PATH      Root mountpoint (default: ${config[ROOT_MNT]})
      --empty MODE         empty disk policy: force|require|refuse

      --log-level LEVEL    DEBUG|INFO|WARN|ERROR|QUIET
      --log-color MODE     auto|always|never

      --dry-run            Show config and exit
      --force              Skip destructive confirmation
  -h, --help               Show this help message and exit.

EOF
}

_validate_disk() {
    local disk type root_dev
    disk="${config[DISK]}"

    if [[ -z $disk || $disk == '__none__' ]]; then
        die 'ERROR: disk not set. Use --disk|-d <value> or --disk=<value>'
    fi

    log_info 'Target disk: %s' "$disk"

    if [[ ! -b $disk ]]; then
        die 'ERROR: %s is not a block device' "$disk"
    fi

    # Get only the first line of TYPE
    type=$(lsblk -no TYPE -- "$disk" 2>/dev/null | head -n1 || true)

    case $type in
        disk|loop) ;;    # OK (and loopback if you want it)
        *)
            log_error 'ERROR: %s has TYPE="%s"; expected a whole device (TYPE=disk)' \
                "$disk" "$type"
            die 'Refusing to operate on partitions or logical volumes.'
            ;;
    esac

    # Guard running root
    root_dev=$(findmnt -n -o SOURCE / || true)
    if [[ -n $root_dev && $root_dev == "$disk"* ]]; then
        die 'ERROR: refusing to operate on current root device: %s' "$disk"
    fi

    # Guard mounted children
    if findmnt -rn -S "${disk}"* >/dev/null 2>&1; then
        log_error 'ERROR: some partitions of %s are currently mounted:' "$disk"
        findmnt -rn -S "${disk}"* >&2 || true
        die 'Refusing destructive operation while partitions are mounted.'
    fi

    log_info 'Disk validated'
}

_confirm_destruction() {
    local disk reply
    disk="${config[DISK]}"

    # Skip prompt for non-interactive / CI runs when explicitly requested
    if [[ ${force:-false} == true ]]; then
        log_info 'Disk destruction confirmation skipped (force=true)'
        return 0
    fi

    log_warn '\nAbout to install onto %s\n' "$disk"
    lsblk "$disk"
    log_warn '\nWARNING: This will ERASE ALL DATA on %s.' "$disk"
    log_warn 'This includes ALL partitions and filesystems shown above.\n'

    # If stdin is not a TTY, refuse to be destructive without --force
    if [[ ! -t 0 ]]; then
        die 'ERROR: Non-interactive session and no --force given; refusing destructive operation.'
    fi

    printf 'Type "yes" to continue: '
    if ! read -r reply; then
        die 'ERROR: Failed to read confirmation; aborting.'
    fi

    if [[ $reply != "yes" ]]; then
        die 'Aborted by user.'
    fi

    log_info 'Proceeding with installation on: %s' "$disk"
}

parse_arguments() {
    local log_level log_color disk_val

    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                _usage_message
                return 0
                ;;

            --dry-run)
                dry_run=true
                shift
                ;;

            --force)
                force=true
                shift
                ;;

            --log-level|-ll)
                if [[ $# -lt 2 ]]; then
                    die 'ERROR: --log-level requires a value'
                fi
                log_level=$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')
                if [[ -n $log_level && -n ${LOG_LEVELS[$log_level]+x} ]]; then
                    config["LOG_LEVEL"]="$log_level"
                    echo "LOG_LEVEL=${config[LOG_LEVEL]}" >&2  # for integration testing
                    shift 2
                else
                    die 'Invalid log level: %s. Valid options are: DEBUG, INFO, WARN, ERROR, QUIET.' \
                        "$log_level"
                fi
                ;;

            --log-level=*)
                log_level=$(printf '%s' "${1#*=}" | tr '[:lower:]' '[:upper:]')
                if [[ -n $log_level && -n ${LOG_LEVELS[$log_level]+x} ]]; then
                    config[LOG_LEVEL]="$log_level"
                    echo "LOG_LEVEL=${config[LOG_LEVEL]}" >&2  # for integration testing
                    shift
                else
                    die 'Invalid log level: %s. Valid options are: DEBUG, INFO, WARN, ERROR, QUIET.' \
                        "$log_level"
                fi
                ;;

            --log-color|-lc)
                if [[ $# -lt 2 ]]; then
                    die 'ERROR: --log-color requires a value'
                fi
                log_color=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')
                case $log_color in
                    auto|always|never)
                        config["LOG_COLOR"]="$log_color"
                        log_debug "config[LOG_COLOR] set to '$log_color'"
                        shift 2
                        ;;
                    *)
                        die 'ERROR: Invalid value for --log-color: %s. Must be one of auto|always|never.' \
                            "$2"
                        ;;
                esac
                ;;

            --log-color=*)
                log_color=$(printf '%s' "${1#*=}" | tr '[:upper:]' '[:lower:]')
                case $log_color in
                    auto|always|never)
                        config["LOG_COLOR"]="$log_color"
                        log_debug "config[LOG_COLOR] set to '$log_color'"
                        shift
                        ;;
                    *)
                        die 'ERROR: Invalid value for --log-color: %s. Must be one of auto|always|never.' \
                            "${1#*=}"
                        ;;
                esac
                ;;

            --disk|-d)
                if [[ $# -lt 2 ]]; then
                    die 'ERROR: --disk requires a value'
                fi
                config[DISK]="$2"
                log_debug "config[DISK] set to '$2'"
                shift 2
                ;;

            --disk=*)
                disk_val=${1#*=}
                if [[ -z $disk_val ]]; then
                    die 'ERROR: --disk= requires a non-empty value'
                fi
                config[DISK]="$disk_val"
                log_debug "config[DISK] set to '$disk_val'"
                shift
                ;;

            --hostname)
                if [[ $# -lt 2 ]]; then
                    die 'ERROR: --hostname requires a value'
                fi
                config[HOSTNAME]="$2"
                shift 2
                ;;

            --hostname=*)
                config[HOSTNAME]=${1#*=}
                shift
                ;;

            --locale)
                if [[ $# -lt 2 ]]; then
                    die 'ERROR: --locale requires a value'
                fi
                config[LOCALE]="$2"
                shift 2
                ;;

            --locale=*)
                config[LOCALE]=${1#*=}
                shift
                ;;

            --keymap)
                if [[ $# -lt 2 ]]; then
                    die 'ERROR: --keymap requires a value'
                fi
                config[KEYMAP]="$2"
                shift 2
                ;;

            --keymap=*)
                config[KEYMAP]=${1#*=}
                shift
                ;;

            --tz)
                if [[ $# -lt 2 ]]; then
                    die 'ERROR: --tz requires a value'
                fi
                config[TZ]="$2"
                shift 2
                ;;

            --tz=*)
                config[TZ]=${1#*=}
                shift
                ;;

            --esp-uuid)
                if [[ $# -lt 2 ]]; then
                    die 'ERROR: --esp-uuid requires a value'
                fi
                config[ESP_UUID]="$2"
                shift 2
                ;;

            --esp-uuid=*)
                config[ESP_UUID]=${1#*=}
                shift
                ;;

            --root-uuid)
                if [[ $# -lt 2 ]]; then
                    die 'ERROR: --root-uuid requires a value'
                fi
                config[ROOT_UUID]="$2"
                shift 2
                ;;

            --root-uuid=*)
                config[ROOT_UUID]=${1#*=}
                shift
                ;;

            --esp-mnt)
                if [[ $# -lt 2 ]]; then
                    die 'ERROR: --esp-mnt requires a value'
                fi
                config[ESP_MNT]="$2"
                shift 2
                ;;

            --esp-mnt=*)
                config[ESP_MNT]=${1#*=}
                shift
                ;;

            --root-mnt)
                if [[ $# -lt 2 ]]; then
                    die 'ERROR: --root-mnt requires a value'
                fi
                config[ROOT_MNT]="$2"
                shift 2
                ;;

            --root-mnt=*)
                config[ROOT_MNT]=${1#*=}
                shift
                ;;

            --empty)
                if [[ $# -lt 2 ]]; then
                    die 'ERROR: --empty requires a value'
                fi
                config[EMPTY]="$2"
                shift 2
                ;;

            --empty=*)
                config[EMPTY]=${1#*=}
                shift
                ;;

            --)
                shift
                break
                ;;

            -*)
                log_error 'ERROR: unknown option: %s' "$1"
                _usage_message >&2
                exit 2
                ;;

            *)
                break
                ;;
        esac
    done

    _validate_disk
    _confirm_destruction

    if [[ ${dry_run:-false} == true ]]; then
        log_info 'Dry run: final config:'
        for k in "${!config[@]}"; do
            printf '%s=%s\n' "$k" "${config[$k]}"
        done | sort
        exit 0
    fi

    return 0
}
