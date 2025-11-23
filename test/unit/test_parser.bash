# Filename: test/unit/test_parser.bats

function setup {
    load '../lib/_common_setup'
    # Load the argument parser
    source src/lib/_parser.bash

    _common_setup
}

@test "smoke test" {
    run true
    assert_success
}
