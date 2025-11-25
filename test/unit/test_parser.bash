###
# In main, _config and _logger are loaded before the _parser. _parser CRUDs the array created by\
# _config and calls functions made available via _logger.
#
# _parser defines three functions,

function setup {
    load '../lib/_common_setup'

    # load the config
    source src/lib/_config.bash

    # load the logger
    source src/lib/_logger.bash

    # Load the argument parser
    source src/lib/_parser.bash

    _common_setup
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
