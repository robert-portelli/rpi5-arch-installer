log_info "Stage $(basename "${BASH_SOURCE[0]}") configure target's network"

: "${config[ROOT_MNT]:?config[ROOT_MNT] must be set}"
: "${config[IPA_TYPE]:?config[IPA_TYPE] must be set}"
: "${config[IFACE]:?config[IFACE] must be set}"

# Validate static-only fields if needed
case "${config[IPA_TYPE]}" in
    STATIC)
        : "${config[IPV4]:?config[IPV4] must be set for STATIC}"
        : "${config[NET_PREFIX]:?config[NET_PREFIX] must be set for STATIC}"
        : "${config[GATEWAY]:?config[GATEWAY] must be set for STATIC}"
        : "${config[DNS1]:?config[DNS1] must be set for STATIC}"
        : "${config[DNS2]:?config[DNS2] must be set for STATIC}"
        ;;
    DHCP)
        # nothing extra required
        ;;
    *)
        log_error "Unsupported IPA_TYPE: ${config[IPA_TYPE]}"
        ;;
esac

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
