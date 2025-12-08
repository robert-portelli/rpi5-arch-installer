# This file defines the loopback device used as the value passed to `--disk` in testing
#
# This file assumes synchronous test execution, i.e., the same image file and subsequent loopback
# device will be used for each test. This is out of respect for host resources over test suite
# execution time.

caller_name="${BATS_TEST_FILENAME:-device_fixture}"
caller_name="$(basename "$caller_name" .bats)"

declare -gA _fixture=(
    # what host resource to use for image file backing: memory or disk
    ## defining the image backing file here means one image file per test script, i.e.,
    ## when the test script sources this file, only one image file is created for all tests in the
    ## test script
    [BACKING_FILE_PATH]="/run/test-device-backing-rpi5-arch-installer-${caller_name}.img"

    # the amount of resource to allocate for image file backing
    # 6 GiB in bytes: # over-provisioned to be under-used; edit to meet available resources
    [BACKING_FILE_SIZE_BYTES]=$((6 * 1024 * 1024 * 1024))

    # the actual loopback device to be passed as value to `--disk`
    [TEST_DEVICE]="__none__"    # to be set by `create_test_device()`
)

create_test_device() {
    # If an external device is supplied, just use it
    if [[ -n "${EXTERNAL_TEST_DEVICE:-}" ]]; then
        echo "Using external test device: $EXTERNAL_TEST_DEVICE"
        _fixture[TEST_DEVICE]="$EXTERNAL_TEST_DEVICE"
        return 0
    fi

    # create / overwrite the backing image file with the desired size
    truncate -s "${_fixture[BACKING_FILE_SIZE_BYTES]}" "${_fixture[BACKING_FILE_PATH]}"

    # sanity check the logical size
    local actual_size
    actual_size=$(stat -c%s "${_fixture[BACKING_FILE_PATH]}") || {
        printf 'ERROR: failed to stat backing file %s\n' "${_fixture[BACKING_FILE_PATH]}" >&2
        return 1
    }

    # reminder: inside arithmetic comparison no $ or "" or {}
    if (( actual_size != _fixture[BACKING_FILE_SIZE_BYTES] )); then
        printf "Error: backing file size (%s) != expected (%s)\n" \
        "$actual_size" "${_fixture[BACKING_FILE_SIZE_BYTES]}" >&2
        return 1
    fi

    # create the loopback device
    local loop_device
    if ! loop_device=$(losetup --show -fP "${_fixture[BACKING_FILE_PATH]}"); then
        printf 'ERROR: failed to create loopback device for %s\n' \
            "${_fixture[BACKING_FILE_PATH]}" >&2
        rm -f "${_fixture[BACKING_FILE_PATH]}"
        return 1
    fi

    # defensive sanity check
    if [[ ! -b "$loop_device" ]]; then
        printf 'ERROR: losetup reported %s, but it is not a block device\n' "$loop_device" >&2
        rm -f "${_fixture[BACKING_FILE_PATH]}"
        return 1
    fi

    echo "Loopback device created: $loop_device"

    # assign the loopback device to the fixture config
    _fixture[TEST_DEVICE]="$loop_device"
}

register_test_device() {
    # is the main config available
    if ! declare -p config &>/dev/null; then
        echo "ERROR: main config unavailable"
        return 1
    fi

    # assign the loopback device to the main config
    config[DISK]="${_fixture[TEST_DEVICE]}"

    # verify the assignment
    if [[ "${config[DISK]}" != "${_fixture[TEST_DEVICE]}" ]]; then
        echo "ERROR: failed to register loopback device with main config"
        return 1
    fi
}

cleanup_test_device() {
    echo "Cleaning up loopback device and image file..."

    # reset the main config if available
    if declare -p config &>/dev/null; then
        config[DISK]='__none__'
    fi

    # If using externally managed device, don't touch loop devices or backing file
    if [[ -n "${EXTERNAL_TEST_DEVICE:-}" ]]; then
        echo "External test device in use; skipping losetup detach and image removal."
        return 0
    fi

    # detach loop device(s) given a backing file
    local loopdev
    while read -r loopdev; do
        [[ -z "$loopdev" ]] && continue
        printf 'Detaching loop device %s\n' "$loopdev" >&2
        losetup -d "$loopdev" || printf 'WARN: failed to detach %s\n' "$loopdev" >&2
    done < <(losetup -j "${_fixture[BACKING_FILE_PATH]}" --output NAME --raw --noheadings)

    # remove backing image file
    if [[ -f "${_fixture[BACKING_FILE_PATH]}" ]]; then
        echo "Removing image file ${_fixture[BACKING_FILE_PATH]}..."
        rm -f "${_fixture[BACKING_FILE_PATH]}" || echo "Failed to remove image file"
    fi

    # verify cleanup
    if losetup -l | grep -q "${_fixture[TEST_DEVICE]}" || [[ -f "${_fixture[BACKING_FILE_PATH]}" ]]; then
        echo "Failed Test Device Cleanup"
        return 1
    fi

    echo "Cleanup complete."

}
