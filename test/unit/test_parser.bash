###
# In main, _config and _logger are loaded before the _parser. _parser CRUDs the array created by\
# _config and calls functions made available via _logger.



# run once before each test case
function setup {
    load '../lib/_common_setup'

    # load the config
    source src/lib/_config.bash

    # load the logger
    source src/lib/_logger.bash

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

@test "--help|-h displays usage message" {
    # capture the usage message
    message=$(_usage_message)

    run parse_arguments --help
    assert_success
    assert_output "$message"

    run parse_arguments -h
    assert_success
    assert_output "$message"
}

@test "--dry-run" {
    run parse_arguments --dry-run --force
    assert_success
}
