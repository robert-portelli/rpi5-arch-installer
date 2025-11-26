#!/usr/bin/env bash
set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly BASE_DIR

cleanup() {
    # unmount root and any mounted children
    if [[ -b "${config[DISK]}" && \
        -n "${config[ROOT_MNT]}" && \
        -n "${config[ROOT_UUID]}" ]]; then

        # 1) Find which device (if any) is mounted at $config[ROOT_MNT]
        local mounted_dev
        mounted_dev="$(lsblk -nr -o NAME,MOUNTPOINT \
            | awk -v m="${config[ROOT_MNT]}" '$2==m {print "/dev/"$1}')"

        if [[ -z "$mounted_dev" ]]; then
            log_debug "Nothing mounted at ${config[ROOT_MNT]}"
            return 0
        fi

        # 2) Get the partition UUID of the device mounted to $config[ROOT_MNT]
        local mounted_uuid
        mounted_uuid="$(lsblk -no PARTUUID "$mounted_dev")"
        log_debug "Device mounted to ${config[ROOT_MNT]}: $mounted_dev (PARTUUID=$mounted_uuid)"

        # If we cannot read PARTUUID or it doesn't match, don't touch it
        if [[ -z "$mounted_uuid" ]]; then
            log_debug "Skipping unmount: no PARTUUID for $mounted_dev"
            return 0
        fi

        if [[ "$mounted_uuid" != "${config[ROOT_UUID]}" ]]; then
            log_debug "Skipping unmount: PARTUUID mismatch (expected ${config[ROOT_UUID]})"
            return 0
        fi

        # 3) Now we know: the device at ROOT_MNT is the one we created
        umount -R "${config[ROOT_MNT]}" >/dev/null 2>&1 || true
        log_info "Unmounting target root at ${config[ROOT_MNT]}"
    fi
}
main() {
    # shellcheck source=src/lib/_config.bash
    source  "$BASE_DIR/src/lib/_config.bash"

    # shellcheck source=src/lib/_logger.bash
    source "$BASE_DIR/src/lib/_logger.bash"

    # shellcheck source=src/lib/_parser.bash
    source "$BASE_DIR/src/lib/_parser.bash"

    parse_arguments "$@"

    log_info "Starting installer (BASE_DIR=${BASE_DIR})"

    for stage in "${BASE_DIR}/src/stages"/*.bash; do
        [[ -f "$stage" ]] || continue

        log_info "Running stage: ${stage##*/}"

        # Dynamic source path is intentional.
        # shellcheck disable=SC1090
        source "$stage"
    done

    log_info "Syncing filesystem buffers with sync(1)"
    sync
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trap cleanup EXIT

    main "$@"

    log_info "Installer completed successfully"
fi
