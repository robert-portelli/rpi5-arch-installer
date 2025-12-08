# rpi5-arch-installer

Automated **bare-metal Arch Linux ARM installation** for the **Raspberry Pi 5**

This project provides a reproducible, idempotent workflow to build a *native-boot* Arch Linux ARM installation using only an x86-64 host with QEMU emulation support.

---

## Purpose

This installer:

- partitions and formats a target disk (NVMe, SSD, USB)
- bootstraps Arch Linux ARM (aarch64) using `pacstrap`
- installs the Raspberry Pi bootloader + kernel (`linux-rpi-16k`)
- configures firmware (`config.txt`, `cmdline.txt`)
- enables locale, keymap, timezone, hostname
- validates all boot assets before exit

The result is a filesystem that boots **directly on a Raspberry Pi 5** with no U-Boot required.

---

## Architecture Overview

The installer is structured as:

- A **configuration module** (`_config.bash`)
- A **printf-style logger** (`_logger.bash`)
- A **CLI parser** (`_parser.bash`)
- A **stage pipeline** under `src/stages/`
- A **main entrypoint** (`src/main.bash`)

Stages execute in lexical order and are idempotent; you may rerun the installer without damaging an already-processed step.

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

```bash
rpi5-arch-installer/
├── .github
│   └── workflows
│       ├── default-branch-protection.yaml
│       ├── non-default-branch-protection.yaml
│       ├── solo-dev-pr-approve.yaml
│       ├── super-linter.yaml
│       ├── test_device_fixture.yaml
│       ├── test_parser.yaml
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
│   │   ├── _logger.bash
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
    ├── lib
    │   ├── _common_setup.bash
    │   ├── _device_fixture.bash
    │   ├── _harness.bash
    │   └── local_harness.bash
    └── unit
        ├── test_common_setup.bats
        ├── test_device_fixture.bats
        └── test_parser.bats
```

---

## Requirements

- Host OS: Arch Linux x86-64 Live ISO or any distro with
  `qemu-user-static`, `qemu-user-binfmt`, `systemd-repart`, and `pacstrap`
- Internet access to Arch Linux ARM mirrors

Target:
Any block device (`/dev/sdX`, `/dev/nvme0n1`) that will become the Pi’s boot disk.

---

## Usage

```bash
# from an Arch Live ISO
git clone https://github.com/robert-portelli/rpi5-arch-installer.git
cd rpi5-arch-installer
```

### Run the installer
```bash
sudo ./src/main.bash --disk=/dev/sdb --hostname=rpi5 --tz=UTC
```

### Common CLI options
```bash
--disk PATH        Required. Target block device.
--hostname NAME    Hostname for installed system.
--locale LOCALE    Default locale (e.g., en_US.UTF-8)
--keymap MAP       Console keymap.
--tz ZONE          Timezone.
--empty MODE       force|require|refuse
--dry-run          Parse args and print final config, then exit.
--force            Skip destructive confirmation.
--log-level LEVEL  DEBUG|INFO|WARN|ERROR|QUIET
--log-color MODE   auto|always|never
```

### Example dry-run

```bash
./src/main.bash --disk=/dev/sdb --dry-run
```

### Example forced installation (CI automation)

```bash
./src/main.bash --disk=/dev/sdb --force
```

---

## Stage Pipeline

|                     Stage | Description                                                         |
| ------------------------: | ------------------------------------------------------------------- |
|          **10_partition** | Creates GPT (ESP + root) using `systemd-repart`.                    |
|              **20_mount** | Mounts ESP and root into `config[ROOT_MNT]`.                        |
|          **30_host_prep** | Imports ALARM GPG key, sets QEMU binfmt, configures pacman.         |
| **40_bootstrap_arch_arm** | Bootstraps base ARM system via `pacstrap -C pacman.arm.conf`.       |
|   **50_rpi5_boot_assets** | Installs kernel, firmware, and writes `config.txt` & `cmdline.txt`. |
|         **60_first_boot** | Applies locale, timezone, hostname, and system identity.            |
|          **99_preflight** | Validates boot assets, fstab, PARTUUIDs, and initramfs.             |

All stages are idempotent

---

## Safety and Validation

Before any destructive action, the parser ensures:

- --disk is provided
- device is a whole disk, not a partition
- device is not the current root
- no partitions of the device are mounted
- destructive confirmation requires typing "yes" unless --force is used

Example confirmation:

```bash
About to install onto /dev/sdb

WARNING: This will ERASE ALL DATA on /dev/sdb.
Type "yes" to continue:
```

## Preflight Checklist

Installer validates:

- Kernel present (Image / kernel8.img)
- Initramfs present (initramfs-linux.img)
- Firmware blobs (start4.elf, fixup4.dat, overlays/)
- Correct cmdline.txt root argument
- Valid config.txt

All checks passing → disk is ready to boot on the Raspberry Pi 5.

---

## Notes

- The target install is **bare-metal** ARM Arch, not a virtual machine.
- This installer does not use U-Boot — it relies on native Raspberry Pi firmware boot.
- Host emulation (QEMU aarch64 binfmt) is used only during build.
- Never mix x86_64 Arch repositories with ARM packages.

---

## Testing

This repository provides a robust test framework for both unit and integration tests, supporting local development and CI workflows. Tests are written in [Bats](https://github.com/bats-core/bats-core) and exercise functionality inside containerized environments, optionally using loopback block devices for disk/installer testing.

### Test Types

- **Unit tests:** Located in `test/unit/`
- **Integration tests:** Located in `test/integration/`
- **Test library scripts:** In `test/lib/`
- **Test harness:** `test/lib/_harness.bash`

---

### Local Testing: Using the Harness

To run tests that require a device fixture (e.g., loopback device):

1. **Provision test device and run tests with the harness:**

   ```sh
   bash test/lib/_harness.bash test_device_fixture.bats
   ```

   This will:
   - Source and configure your device and test fixture
   - Create and register a loopback device (e.g., `/dev/loop0`)
   - Spawn a test container with the device mapped in and run the specified Bats test

2. **Running arbitrary tests:**

   You may specify any test file (searched recursively below `test/`):

   ```sh
   bash test/lib/_harness.bash <test_name>.bats
   ```

   Example for an integration test:
   ```sh
   bash test/lib/_harness.bash integration_device_flow.bats
   ```

3. ** Running arbitrary tests directly on your host:**

    ```sh
    bats test/unit/test_device_fixture.bats
    ```

---

### Advanced: Local GitHub Actions Workflow with ACT

You can simulate GitHub Actions runs locally using [nektos/act](https://github.com/nektos/act), which lets you verify your workflows and test container interactions in a local Docker environment.

#### **Automated Workflow Harness**

A script `test/local_harness.bash` sets up the loopback device and invokes `act` with the required device mapping and environment variables.

```sh
# Usage: (from repo root)
bash test/local_harness.bash job=test-device-fixture
```

This script will:
- Source repo config and device fixture scripts
- Provision and register a loop device and backing file
- Set `DEVICE` and `EXTERNAL_TEST_DEVICE` environment variables
- Invoke `gh act` (the GitHub CLI act extension) with:
  - `--container-options "--device=$DEVICE"`
  - `--env EXTERNAL_TEST_DEVICE=$DEVICE`
- Automatically clean up loop and file resources after the run

**Note:** You must have [gh (GitHub CLI)](https://cli.github.com/) and the [gh-act extension](https://github.com/nektos/gh-act) installed.

---

### Continuous Integration

- All tests are also run under GitHub Actions in `.github/workflows/`
- The CI workflow provisions required packages and runs the harness as above using a prebuilt test image, ensuring that device fixtures and all required system tools are present

---

### General Notes

- Containers are orchestrated with all necessary device and capability flags (e.g., `--device`, `--cap-add=SYS_ADMIN`)
- The test harness ensures resources (devices, files) are cleaned up via shell traps even on error or interrupt
- Tests that require a device fixture accept the device via `EXTERNAL_TEST_DEVICE` or create their own if not provided
- All backing files and loop devices are temporary and cleaned up on exit

---

### Troubleshooting

- If you see errors about `uuidgen` or devices not found, ensure all system dependencies are installed in your test containers and that device creation is permitted (requires privileges).
- On CI, everything is provisioned automatically; for local testing, make sure you run from the repository root directory.

---

### Useful Commands

```sh
# Run a single test locally (unit or integration)
bash test/lib/_harness.bash test_device_fixture.bats

# Run a workflow via ACT with device provisioned
bash test/local_harness.bash job=test-device-fixture

# (Optional) Clean up leftover loop devices manually:
sudo losetup -D
```

---

**See comments in `test/lib/_harness.bash` and `test/local_harness.bash` for detailed developer instructions.**

---

## License

See [LICENSE.md](LICENSE.md) for terms.
