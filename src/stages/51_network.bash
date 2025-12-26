#'config' is provided by src/lib/_config.bash sourced in main.bash.
# shellcheck disable=SC2154

log_info "Stage $(basename "${BASH_SOURCE[0]}") configure target's network"

WIRED="${config[ROOT_MNT]}/etc/systemd/network/20-${config[IFACE]}.network"

dhcp() {
    cat >"$WIRED" <<EOF
[Match]
Name=${config[IFACE]}

[Network]
DHCP=yes
EOF
}

static() {
    cat >"$WIRED" <<EOF
[Match]
Name=${config[IFACE]}

[Network]
DHCP=no
Address=${config[IPV4]}/${config[NET_PREFIX]}
Gateway=${config[GATEWAY]}
DNS=${config[DNS1]}
DNS=${config[DNS2]}
IPv6AcceptRA=no
EOF
}


if ! arch-chroot "${config[ROOT_MNT]}" systemctl enable systemd-networkd systemd-resolved ; then
    log_error "Failed to enable the target's systemd-networkd or systemd-resolved."
fi

if ! install -D -m0644 /dev/null "$WIRED" ; then
    log_error "Failed to create wired config: $WIRED"
fi


case "${config[IPA_TYPE]}" in
    DHCP)
        dhcp
        ;;
    STATIC)
        static
        ;;
    *)
       log_error "Unsupported IPA_TYPE: ${config[IPA_TYPE]}"
        ;;
esac

arch-chroot "${config[ROOT_MNT]}" ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
