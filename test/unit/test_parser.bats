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

    _logger_init
    # the calls to parse_arguments requires a valid disk, even for --dry-run
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

@test "--help|-h" {
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

@test "--log-level|-ll" {
    # test valid config[LOG_LEVEL] values
    local -a valid=(
        "INFO INFO"
        "iNfO INFO"
        "DEBUG DEBUG"
        "WARN WARN"
        "ERROR ERROR"
        "error ERROR"
        "QUIET QUIET"
    )

    local input expected entry

    for entry in "${valid[@]}"; do
        read -r input expected <<<"$entry"

        run parse_arguments --dry-run --force --log-level "$input"
        assert_success
        assert_output -p LOG_LEVEL="$expected"

        run parse_arguments --dry-run --force -ll "$input"
        assert_success
        assert_output -p LOG_LEVEL="$expected"
    done

    # test invalid config[LOG_LEVEL] values
    run parse_arguments --dry-run --force --log-level INVALID
    assert_failure
    assert_output -p Invalid log level: INVALID. Valid options are: DEBUG, INFO, WARN, ERROR, QUIET.

    run parse_arguments --dry-run --force --log-level
    assert_failure
    assert_output -p ERROR: --log-level requires a value

    run parse_arguments --dry-run --force -ll INVALID
    assert_failure
    assert_output -p Invalid log level: INVALID. Valid options are: DEBUG, INFO, WARN, ERROR, QUIET.

    run parse_arguments --dry-run --force -ll
    assert_failure
    assert_output -p ERROR: -ll requires a value
}


@test "--log-level=*" {
    # test valid config[LOG_LEVEL] values
    declare -a valid=(
        "INFO INFO"
        "info INFO"
        "DEBUG DEBUG"
        "dEBug DEBUG"
        "WARN WARN"
        "ERROR ERROR"
        "error ERROR"
        "QUIET QUIET"
    )

    local entry input expected

    for entry in "${valid[@]}"; do
        read -r input expected <<<"$entry"
        run parse_arguments --dry-run --force --log-level="$input"
        assert_success
        assert_output -p LOG_LEVEL="$expected"
    done

    ## test invalid log levels
    run parse_arguments --dry-run --force --log-level=INVALID
    assert_failure
    assert_output -p Invalid log level: INVALID. Valid options are: DEBUG, INFO, WARN, ERROR, QUIET.

    run parse_arguments --dry-run --force --log-level=
    assert_failure
    assert_output -p ERROR: --log-level requires a value
}

@test "--log-color|-lc" {
    # test valid config[LOG_COLOR] values
    declare -a valid=(
        "always always"
        "ALWAYS always"
        "AlwAYs always"
        "auto auto"
        "never never"
        "Never never"
    )

    local entry input expected

    for entry in "${valid[@]}"; do
        read -r input expected <<<"$entry"
        run parse_arguments --dry-run --force --log-color "$input"
        assert_success
        assert_output -p LOG_COLOR="$expected"
        run parse_arguments --dry-run --force -lc "$input"
        assert_success
        assert_output -p LOG_COLOR="$expected"
    done

    # test invalid config[LOG_COLOR] values
    run parse_arguments --dry-run --force --log-color invalid
    assert_failure
    assert_output -p 'ERROR: Invalid value for --log-color: invalid. Must be one of auto|always|never.'

    run parse_arguments --dry-run --force --log-color
    assert_failure
    assert_output -p "ERROR: --log-color requires a value"

    run parse_arguments --dry-run --force -lc invalid
    assert_failure
    assert_output -p 'ERROR: Invalid value for -lc: invalid. Must be one of auto|always|never.'

    run parse_arguments --dry-run --force -lc
    assert_failure
    assert_output -p "ERROR: -lc requires a value"
}

@test "--log-color=*" {
    ## test valid config[LOG_COLOR] values
    declare -a valid=(
        "always always"
        "ALWAYS always"
        "AlwAYs always"
        "auto auto"
        "never never"
        "Never never"
    )

    local entry input expected

    for entry in "${valid[@]}"; do
        read -r input expected <<<"$entry"
        run parse_arguments --dry-run --force --log-color="$input"
        assert_success
        assert_output -p LOG_COLOR="$expected"
    done

    ## test invalid config[LOG_COLOR] values
    run parse_arguments --dry-run --force --log-color=INVALID
    assert_failure
    assert_output -p "ERROR: Invalid value for --log-color: invalid. Must be one of auto|always|never."

    run parse_arguments --dry-run --force --log-color=
    assert_failure
    assert_output -p "ERROR: --log-color requires a value"
}

@test "--disk|-d" {
    # omitted value
    run parse_arguments --dry-run --force --disk
    assert_failure
    assert_output -p ERROR: --disk requires a value
    run parse_arguments --dry-run --force -d
    assert_failure
    assert_output -p ERROR: --disk requires a value

    # not block device
    invalid="$(mktemp)"
    run parse_arguments --dry-run --force --disk "$invalid"
    assert_failure
    assert_output -p ERROR: invalid is not a block device
    run parse_arguments --dry-run --force -d "$invalid"
    rm "$invalid"

    # value is partition not whole disk


    # value is current root
    ## chroot?


    # value is whole disk but has mounted partition(s)


    # valid disk value
    run parse_arguments --dry-run --force   # config contains a valid disk via setup()
    assert_success
    assert_output -p Disk validated
}

@test "--hostname|--hostname=*" {
    run parse_arguments --dry-run --force --hostname bats-test
    assert_success
    assert_output -p HOSTNAME=bats-test
    run parse_arguments --dry-run --force --hostname=bats-test
    assert_success
    assert_output -p HOSTNAME=bats-test
}

@test "--empty" {
    run parse_arguments --dry-run --force --empty
    assert_failure
    assert_output -p "ERROR: --empty requires a value"

    run parse_arguments --dry-run --force --empty invalid
    assert_failure
    assert_output -p "ERROR: Invalid value for --empty: invalid"

    run parse_arguments --dry-run --force --empty force
    assert_success
    assert_output -p EMPTY=force

    run parse_arguments --dry-run --force --empty FORCE
    assert_success
    assert_output -p EMPTY=force

    run parse_arguments --dry-run --force --empty refuse
    assert_success
    assert_output -p EMPTY=refuse

    run parse_arguments --dry-run --force --empty ReFUse
    assert_success
    assert_output -p EMPTY=refuse

    run parse_arguments --dry-run --force --empty require
    assert_success
    assert_output -p EMPTY=require

    run parse_arguments --dry-run --force --empty REQuire
    assert_success
    assert_output -p EMPTY=require
}
@test "--ipa-type" {
    run parse_arguments --dry-run --force --ipa-type
    assert_failure
    assert_output -p "ERROR: --ipa-type requires a value"

    run parse_arguments --dry-run --force --ipa-type invalid
    assert_failure
    assert_output -p "ERROR: Invalid value for --ipa-type"
    run parse_arguments --dry-run --force --ipa-type static
    assert_success

    run parse_arguments --dry-run --force --ipa-type dhcp
    assert_success
    assert_output -p "IPA_TYPE=DHCP"

    run parse_arguments --dry-run --force --ipa-type DhCp
    assert_success
    assert_output -p "IPA_TYPE=DHCP"

    run parse_arguments --dry-run --force --ipa-type static
    assert_success
    assert_output -p "IPA_TYPE=STATIC"

    run parse_arguments --dry-run --force --ipa-type StaTIC
    assert_success
    assert_output -p "IPA_TYPE=STATIC"
}

@test "--interface" {
    run parse_arguments --dry-run --force --interface
    assert_failure
    assert_output -p "ERROR: --interface requires a value"

    run parse_arguments --dry-run --force --interface eth0
    assert_success
    assert_output -p "IFACE=eth0"
}

@test "--ipv4" {
    run parse_arguments --dry-run --force --ipv4
    assert_failure
    assert_output -p "ERROR: --ipv4 requires a value"
    run parse_arguments --dry-run --force --ipv4 10.0.0.127
    assert_success
    assert_output -p "IPV4=10.0.0.127"
}

@test "--net-prefix" {
    run parse_arguments --dry-run --force --net-prefix
    assert_failure
    assert_output -p "ERROR: --net-prefix requires a value"

    run parse_arguments --dry-run --force --net-prefix 96
    assert_success
    assert_output -p "NET_PREFIX=96"
}

@test "--gateway" {
    run parse_arguments --dry-run --force --gateway
    assert_failure
    assert_output -p "ERROR: --gateway requires a value"

    run parse_arguments --dry-run --force --gateway 10.0.0.111
    assert_success
    assert_output -p "GATEWAY=10.0.0.111"
}

@test "--dns1" {
    run parse_arguments --dry-run --force --dns1
    assert_failure
    assert_output -p "ERROR: --dns1 requires a value"

    run parse_arguments --dry-run --force --dns1 1.2.3.4
    assert_success
    assert_output -p "DNS1=1.2.3.4"
}

@test "--dns2" {
    run parse_arguments --dry-run --force --dns2
    assert_failure
    assert_output -p "ERROR: --dns2 requires a value"

    run parse_arguments --dry-run --force --dns2 4.3.2.1
    assert_success
    assert_output -p "DNS2=4.3.2.1"
}

@test "unsupported flag" {
    run parse_arguments --dry-run --force --invalid
    assert_failure
    assert_output -p "ERROR: unknown option: --invalid"
}
