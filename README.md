# rpi5-arch-installer

Automated **bare-metal Arch Linux ARM installation** for the **Raspberry Pi 5**

---

## Purpose

This project provides a reproducible, idempotent way to provision a bootable Arch Linux ARM system disk for the Raspberry Pi 5.
It runs entirely from an x86-64 host or Arch Live ISO and performs all steps needed to produce a native-bootable Pi 5 installation: partitioning, formatting, base system bootstrap, kernel and firmware installation, and firmware configuration.

---

## Stage Overview

| Stage | Description |
|:------|:-------------|
| **10_partition_format** | Create GPT layout (ESP + root-arm64) using `systemd-repart`. |
| **20_mount** | Mount ESP and root partitions under `/mnt` and `/mnt/boot`. |
| **30_host_prep** | Import the Arch Linux ARM GPG key, install QEMU emulation, and configure ARM pacman mirrors. |
| **40_bootstrap_arch_arm** | Bootstrap the ARM base system with `pacstrap -C pacman.arm.conf`. |
| **50_rpi5_boot_assets** | Install `linux-rpi-16k`, firmware, and generate `config.txt` and `cmdline.txt`. |
| **60_first_boot** | Apply locale, timezone, hostname, and first-boot identity via `systemd-firstboot`. |
| **99_preflight** | Validate kernel, initramfs, firmware, fstab, and configuration readiness. |

Each stage is idempotent—re-running the installer leaves unchanged targets intact.
Stages execute in lexical order, allowing new steps to be added easily.

---

## Directory Layout

```
rpi5-arch-installer/
├── .github
│   └── workflows
│       ├── default-branch-protection.yaml
│       ├── non-default-branch-protection.yaml
│       ├── solo-dev-pr-approve.yaml
│       ├── super-linter.yaml
│       └── test_test_environment.yaml
├── .gitignore
├── .pre-commit-config.yaml
├── Makefile
├── README.md
├── docker
│   └── test
│       └── Dockerfile
├── src
│   ├── lib
│   │   ├── _config.bash
│   │   └── _parser.bash
│   ├── main.bash
│   └── stages
│       ├── 10_partition_format.bash
│       ├── 20_mount.bash
│       ├── 30_host_prep.bash
│       ├── 40_bootstrap_arch_arm.bash
│       ├── 50_rpi5_boot_assets.bash
│       ├── 60_first_boot.bash
│       └── 99_preflight.bash
└── test
    ├── test_common_setup.bats
    └── test_helpers
        └── _common_setup.bash
```

---

## Requirements

- Host OS: Arch Linux x86-64 Live ISO or any distro with
  `qemu-user-static`, `qemu-user-binfmt`, `systemd-repart`, and `pacstrap`
- Internet access to Arch Linux ARM mirrors
- Target disk: Device connected to host

---

## Usage

```bash
# from an Arch Live ISO
git clone https://github.com/robert-portelli/rpi5-arch-installer.git
cd rpi5-arch-installer

# optional overrides
export DISK=/dev/nvme0n1
export HOSTNAME=rpi5
export TZ=UTC

# run all stages
bash src/installer.sh
```
---

## Makefile Targets (planned)

| Target | Description |
|---------|-------------|
| `make all` | Run full installation pipeline |
| `make test` | Run Bats tests |
| `make clean` | Unmount and remove build artifacts |
| `make lint` | Run shellcheck and formatting checks |
| `make release` | Prepare release archive and tag |

---

## Preflight Checklist

After completion the installer reports any missing:
- Kernel (`Image` or `kernel8.img`)
- Initramfs (`initramfs-linux.img`)
- Firmware blobs (`start4.elf`, `fixup4.dat`, `overlays/`)
- Correct `fstab` entries with `PARTUUID`
- Proper `config.txt` / `cmdline.txt` configuration

All checks passing → system is ready to boot on the Pi 5.

---

## Notes

- The target install is **bare-metal** ARM Arch, not a virtual machine.
- Host emulation (QEMU aarch64 binfmt) is used only during build.
- Never mix x86_64 Arch repositories with ARM packages.

---

## License

See [LICENSE.md](LICENSE.md) for terms.
