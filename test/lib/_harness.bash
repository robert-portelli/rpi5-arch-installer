#! /usr/bin/env bash
set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly BASE_DIR

# Find a test file by name in $BASE_DIR/test (all subdirs)
find_test_file() {
    local test_name="$1"
    local found_file
    # Search for test file (full match, all subdirs), prioritising first found
    found_file=$(find "$BASE_DIR/test" -type f -name "$test_name" | head -n1)
    if [[ -z "$found_file" ]]; then
        echo "ERROR: Test file '$test_name' not found in $BASE_DIR/test" >&2
        return 1
    fi
    echo "$found_file"
}

device_fixture() {
    source "$BASE_DIR/test/lib/_device_fixture.bash"
    create_test_device
    register_test_device
}

test_container() {
    local TEST_PATH="$1"
    docker run --rm \
        --device="${_fixture[TEST_DEVICE]}" \
        --cap-add=SYS_ADMIN \
        -v "$PWD:$PWD" -w "$PWD" \
        -e EXTERNAL_TEST_DEVICE="${_fixture[TEST_DEVICE]}" \
        robertportelli/rpi5-arch-installer:latest \
        bats "$TEST_PATH"
}

cleanup() {
    if declare -F cleanup_test_device &>/dev/null; then
        cleanup_test_device
    fi
}

main() {
    source "$BASE_DIR/src/lib/_config.bash"
    if [[ $# -ne 1 ]]; then
        echo "Usage: $0 <test_name.bats>" >&2
        exit 2
    fi
    local TEST_PATH
    TEST_PATH=$(find_test_file "$1") || exit 1
    device_fixture
    test_container "$TEST_PATH"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trap cleanup EXIT

    main "$@"

fi
