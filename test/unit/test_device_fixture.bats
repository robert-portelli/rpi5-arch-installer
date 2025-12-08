# run once before each test case
function setup {
    load '../lib/_common_setup'

    # load the config
    source src/lib/_config.bash

    # Load the test device fixture library
    source test/lib/_device_fixture.bash

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

@test "_fixture config array" {
    run declare -p _fixture
    assert_success
    assert_equal "${_fixture[BACKING_FILE_PATH]}" \
        "/run/test-device-backing-rpi5-arch-installer-test_device_fixture.img"
    assert_equal "${_fixture[BACKING_FILE_SIZE_BYTES]}" 6442450944
    assert_equal "${_fixture[TEST_DEVICE]}" "__none__"
}

@test "create_test_device()" {
    create_test_device
    # Only check backing file if not using external device
    if [[ -z "${EXTERNAL_TEST_DEVICE:-}" ]]; then
        assert_file_exists "${_fixture[BACKING_FILE_PATH]}"
    fi
    assert [ -b "${_fixture[TEST_DEVICE]}" ]
    register_test_device # the cleanup depends on it being registered
}

@test "run create_test_device()" {
    run create_test_device
    assert_success
    register_test_device # for cleanup to work
}
