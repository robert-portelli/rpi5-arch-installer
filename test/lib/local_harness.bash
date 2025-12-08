#!/usr/bin/env bash
set -euo pipefail

# Allow for input: ./local_harness.bash job=test-device-fixture [any other options]
JOB=${job:-test-device-fixture}

# -- Setup: source repo scripts
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$BASE_DIR/src/lib/_config.bash"
source "$BASE_DIR/test/lib/_device_fixture.bash"

# -- Create the loop device
create_test_device
register_test_device

DEVICE="${_fixture[TEST_DEVICE]}"

# -- Cleanup function for exit/interrupts
cleanup() {
    if declare -F cleanup_test_device &>/dev/null; then
        cleanup_test_device
    fi
}
trap cleanup EXIT

echo "Will use device $DEVICE in workflow $JOB"
echo "Provisioned backing file: ${_fixture[BACKING_FILE_PATH]}"

# -- Call ACT via gh extension with device mapped in
gh act -j "$JOB" \
    --container-options "--device=$DEVICE" \
    --env EXTERNAL_TEST_DEVICE="$DEVICE"

# cleanup will run on exit/trap
