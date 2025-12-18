# shellcheck disable=SC2030,SC2031
# run once before each test case
function setup {
    # load the bats setups
    load '../lib/_common_setup'

    # load the config
    source src/lib/_config.bash

    # set the log level
    config[LOG_LEVEL]="DEBUG"
    # load the logger
    source src/lib/_logger.bash

    _logger_init

    # Load the argument parser
    source src/lib/_parser.bash

    # Load the test device fixture library
    source test/lib/_device_fixture.bash
    create_test_device
    register_test_device

    _common_setup
}

# run once after each test case
function teardown {
    cleanup_test_device
}

@test "smoke test" {
    run true
    assert_success
    run false
    assert_failure
}

@test "stage 10: end-to-end" {
    run source src/stages/10_partition_format.bash
    assert_success
}

@test "stage 10: partitions and formats test disk as expected" {
    # run the stage
    source src/stages/10_partition_format.bash
}

stage_10_placeholder() {
    local disk="${config[DISK]}"
    local p1="${disk}p1"
    local p2="${disk}p2"

    #
    # 1) config[DISK] has two partitions
    #
    run lsblk -no NAME "$disk"
    assert_success
    # output is e.g.:
    #   loop0
    #   loop0p1
    #   loop0p2
    local count
    count=$(printf '%s\n' "$output" | wc -l)
    [[ "$count" -eq 3 ]]

    #
    # 2) partition 1 is label ESP and type esp
    #
    # Label
    run lsblk -no PARTLABEL "$p1"
    assert_success
    [[ "$output" == "ESP" ]]

    # Type (GUID) – systemd’s "esp" maps to a specific GPT type GUID.
    # Use PARTTYPE to assert it matches the expected GUID for ESP.
    # Look up the correct GUID and replace <ESP_GUID> with it.
    run lsblk -no PARTTYPE "$p1"
    assert_success
    [[ "$output" == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" ]]

    #
    # 3) partition 1 is UUID config[ESP_UUID]
    #
    # For PARTUUID, lsblk is convenient:
    run lsblk -no PARTUUID "$p1"
    assert_success
    [[ "$output" == "${config[ESP_UUID]}" ]]

    #
    # 4) partition 1 has filesystem FAT32
    #
    # Either lsblk:
    run lsblk -no FSTYPE "$p1"
    assert_success
    [[ "$output" == "vfat" ]]

    # Or blkid (alternative):
    # run blkid -o value -s TYPE "$p1"
    # assert_success
    # [[ "$output" == "vfat" ]]

    #
    # 5) partition 2 is label root and type root-arm64
    #
    # Label
    run lsblk -no PARTLABEL "$p2"
    assert_success
    [[ "$output" == "root" ]]

    # Type (GUID) – systemd’s "root-arm64" also maps to a GPT type GUID.
    # Replace <ROOT_ARM64_GUID> with the correct GUID.
    run lsblk -no PARTTYPE "$p2"
    assert_success
    [[ "$output" == "b921b045-1df0-41c3-af44-4c6f280d3fae" ]]

    #
    # 6) partition 2 is UUID config[ROOT_UUID]
    #
    run lsblk -no PARTUUID "$p2"
    assert_success
    [[ "$output" == "${config[ROOT_UUID]}" ]]

    #
    # 7) partition 2 is filesystem BTRFS
    #
    run lsblk -no FSTYPE "$p2"
    assert_success
    [[ "$output" == "btrfs" ]]

    # Or blkid:
    # run blkid -o value -s TYPE "$p2"
    # assert_success
    # [[ "$output" == "btrfs" ]]
}
