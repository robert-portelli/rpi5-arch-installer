# This Dockerfile sets up an environment for testing the functionality defined in this repository.
# It is not intended for production or deployment purposes.

FROM archlinux:latest

RUN pacman-key --init && \
    pacman-key --populate archlinux && \
    pacman -Syyu --noconfirm && \
    pacman -S --noconfirm reflector && \
    reflector --latest 5 --protocol https --sort rate --save /etc/pacman.d/mirrorlist && \
    pacman -Syy --noconfirm && \
    pacman -S --noconfirm \
        bats-assert bats-file bats-support \
        nodejs npm \
        util-linux \
        arch-install-scripts \
        btrfs-progs parted dosfstools \
        pacman-contrib && \
    pacman -Scc --noconfirm   # clean cache

WORKDIR /workspace
CMD ["/bin/bash"]
