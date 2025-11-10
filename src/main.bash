#!/usr/bin/env bash
set -u
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly BASE_DIR

main() {
    # shellcheck source=src/lib/_config.bash
    source  "$BASE_DIR/src/lib/_config.bash"

    for stage in "${BASE_DIR}/src/stages"/*.bash; do
        [[ -f "$stage" ]] || continue

        # Dynamic source path is intentional.
        # shellcheck disable=SC1090
        source "$stage"
    done

    sync
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    umount -R "${config[ROOT_MNT]}"
 fi
