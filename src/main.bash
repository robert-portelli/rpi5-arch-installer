#!/usr/bin/env bash

set -u
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly BASE_DIR

main() {
    # shellcheck source=src/lib/_config.bash
    source  "$BASE_DIR/src/lib/_config.bash"

    # source the parser

    # shellcheck source=src/lib/_logger.bash
    source "$BASE_DIR/src/lib/_logger.bash"

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
    trap 'umount -R "${config[ROOT_MNT]}"' EXIT
    log_info "Invoked as top-level script, entering main()"
    main "$@"
    log_info "Unmounting target root at ${config[ROOT_MNT]}"
    log_info "Installer completed successfully"
fi
