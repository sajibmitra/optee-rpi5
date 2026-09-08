# Raspberry Pi 5 real OP-TEE

Build, deploy, and test **real OP-TEE** on Raspberry Pi 5 (embedded armstub + custom OP-TEE kernel + LAN scripts).

This repository is also the experimental base for **Hybrid QAI (Quantum AI) deployment in OP-TEE**: keep Trusted Applications small and deterministic, run sensitive inference / model parameters in the TEE, and measure REE↔TEE behaviour on physical hardware.

## Research milestone timeline (QAI on OP-TEE)

Chronology of achieved milestones for this research track (Raspberry Pi 5 + real OP-TEE → Hybrid QAI prototype).

| When | Milestone | Outcome | Docs |
| ---- | --------- | ------- | ---- |
| **2026-08 (late)** | Platform bring-up | TF-A armstub, OP-TEE OS, OP-TEE-enabled kernel, userspace (`optee_client` / `xtest`), and LAN deploy scripts landed in-repo. Secure World boots on Pi 5. | [`docs/README.md`](docs/README.md) |
| **2026-08-29** | Repo / reproducible port | Initial `pi5-optee` tree published: scripts, artifacts, docs, vendored ATF / OP-TEE OS / client / test trees. | [`docs/README.md`](docs/README.md) |
| **2026-08-31** | Regression validation | Full OP-TEE regression suite exercised on device; **114/114** cases passed (after plugin fix). Pre-built SD image published for fast replication. On-Pi `xtest` self-build guide added. | [`docs/build-xtest-on-rpi5.md`](docs/build-xtest-on-rpi5.md) |
| **2026-08-31** | Platform documentation | Platform manual (`docs/rpi5-optee-manual.*`) and operator docs frozen as the infrastructure baseline. | [`docs/README.md`](docs/README.md) · PDF: [`docs/rpi5-optee-manual.pdf`](docs/rpi5-optee-manual.pdf) |
| **2026-09-02** | QAI research plan | Hybrid QAI roadmap written: do **not** put full Qiskit/PennyLane in a TA; target REE features → TEE TinyML/QAI inference. | [`docs/qai-optee-prototype-roadmap.md`](docs/qai-optee-prototype-roadmap.md) |
| **2026-09-08** | `qai_ta` prototype (Phases 2–10) | Dedicated TA + host under `optee_examples/qai_ta/`: baseline C inference, TinyML logistic model, quantum-inspired hybrid kernel, protected (encrypt-in-REE / decrypt-in-TEE) path, REE↔TEE timing harness, offline trainers. | [`docs/qai-optee-architecture.md`](docs/qai-optee-architecture.md) · [`optee_examples/qai_ta/README.md`](optee_examples/qai_ta/README.md) |
| **2026-09-08** | Physical Pi validation | Deployed to `skmitra@172.20.10.2`. Baseline demo `[10, 20, -5, 3]` → **Prediction 1**, **Confidence 28**; TinyML / QAI / protected modes and `--bench` latency measured (~10–11 ms TEE invoke). Running manual published. | [`docs/qai-optee-running-manual.md`](docs/qai-optee-running-manual.md) |

### Milestone map (roadmap phases)

| ID | Status | Milestone | Primary docs |
| -- | ------ | --------- | ------------ |
| M1 | ✓ | OP-TEE on Raspberry Pi 5 + REE↔TEE (`xtest` / hello path) | [`docs/build-xtest-on-rpi5.md`](docs/build-xtest-on-rpi5.md) · [`docs/README.md`](docs/README.md) |
| M2 | ✓ | Clean `qai_ta` (not `hello_world` forks) | [`docs/qai-optee-prototype-roadmap.md`](docs/qai-optee-prototype-roadmap.md) · [`optee_examples/qai_ta/README.md`](optee_examples/qai_ta/README.md) |
| M3 | ✓ | C inference inside TEE | [`docs/qai-optee-prototype-roadmap.md`](docs/qai-optee-prototype-roadmap.md) · [`docs/qai-optee-running-manual.md`](docs/qai-optee-running-manual.md) |
| M4 | ✓ | REE → QAI TA → REE client with timing | [`docs/qai-optee-running-manual.md`](docs/qai-optee-running-manual.md) |
| M5 | ✓ | Offline TinyML train → params in TA | [`docs/qai-optee-running-manual.md`](docs/qai-optee-running-manual.md) (§8) · [`docs/qai-optee-prototype-roadmap.md`](docs/qai-optee-prototype-roadmap.md) |
| M6 | ✓ | Quantum-inspired hybrid params (host train → compact TA kernel) | [`docs/qai-optee-prototype-roadmap.md`](docs/qai-optee-prototype-roadmap.md) · [`docs/qai-optee-architecture.md`](docs/qai-optee-architecture.md) |
| M7 | ✓ | Security-sensitive model resident in OP-TEE | [`docs/qai-optee-architecture.md`](docs/qai-optee-architecture.md) |
| M8 | ✓ | Protected feature path (prototype) | [`docs/qai-optee-running-manual.md`](docs/qai-optee-running-manual.md) (§6.5) · [`docs/qai-optee-architecture.md`](docs/qai-optee-architecture.md) |
| M9 | ✓ | Measurement harness (REE vs TEE latency / model size hints) | [`docs/qai-optee-running-manual.md`](docs/qai-optee-running-manual.md) (§6.7–6.8) |
| M10 | ✓ | Documented Hybrid QAI architecture + run manual | [`docs/qai-optee-architecture.md`](docs/qai-optee-architecture.md) · [`docs/qai-optee-running-manual.md`](docs/qai-optee-running-manual.md) |

### Docs index (`docs/`)

| Document | Purpose |
| -------- | ------- |
| [`docs/README.md`](docs/README.md) | Documentation index (platform + QAI) |
| [`docs/build-xtest-on-rpi5.md`](docs/build-xtest-on-rpi5.md) | Build / verify `xtest` on the Pi |
| [`docs/qai-optee-prototype-roadmap.md`](docs/qai-optee-prototype-roadmap.md) | Hybrid QAI research roadmap (Phases 1–10) |
| [`docs/qai-optee-architecture.md`](docs/qai-optee-architecture.md) | Trust split, TA commands, security claim |
| [`docs/qai-optee-running-manual.md`](docs/qai-optee-running-manual.md) | Build, deploy, run, measure, troubleshoot |
| [`docs/rpi5-optee-manual.pdf`](docs/rpi5-optee-manual.pdf) | Platform OP-TEE manual (PDF; source `.tex`) |

### Next research steps (not yet claimed)

- Stronger crypto than prototype XOR (TEE AES / secure storage for keys)
- Broader datasets + accuracy tables (REE vs TEE parity)
- Energy / CPU util traces for publications
- Optional: attested model provisioning

How to reproduce the current QAI milestone: see [`docs/qai-optee-running-manual.md`](docs/qai-optee-running-manual.md).

## Quick start

### Option 1: Use Pre-built SD Card Image (Fastest)

A validated, pre-built SD card image is available on Google Drive. This image contains a complete, tested OP-TEE environment ready to use.

**Download:** [Raspberry Pi 5 OP-TEE SD Card Image](https://drive.google.com/file/d/1VSLtJFr75WE-CwRTMUFp2P5EHyy8jKpu/view?usp=drive_link)

**Image Contents:**
- Custom Linux kernel with OP-TEE support
- ARM Trusted Firmware (TF-A) bootloader
- OP-TEE OS (secure world)
- OP-TEE userspace libraries and tools
- Trusted Applications (TAs)
- Testing tools and validation suite

**Validation Status:**
✅ All 114 OP-TEE regression test cases passed (after resolving missing plugin issue)

**Default Credentials:**
- Username: `skmitra`
- Password: `testP!26`

**Installation:**
1. Download the image from Google Drive
2. Extract the compressed image: `gunzip rpi5-optee.img.gz`
3. Follow the [Flush Raspberry Pi Image to SD Card](#flush-raspberry-pi-image-to-sd-card) instructions below
4. Insert SD card into Raspberry Pi 5 and power on

### Option 2: Build from Source

```bash
# Build firmware + userspace overlay
OPTEE_MAX_LOG=1 ./build-rpi5-optee.sh
./build-rpi5-optee-kernel.sh

# Deploy over LAN (prefer Ethernet for first reboot)
export PI_SUDO_PASSWORD='...'
./deploy_rpi5_optee_kernel.sh --skip-build --skip-kernel-config-fetch USER@PI_LAN_IP

# Validate
./testing_rpi5_optee_kernel.sh USER@PI_LAN_IP
```

## Documentation

- LaTeX / PDF: `docs/rpi5-optee-manual.tex`, `docs/rpi5-optee-manual.pdf`
- QAI running manual: `docs/qai-optee-running-manual.md`
- QAI prototype roadmap: `docs/qai-optee-prototype-roadmap.md`
- QAI TA example: `optee_examples/qai_ta/` (build/deploy via `scripts/` there)
- Memory layout: `artifacts/rpi5-optee/MEMORY-LAYOUT.txt`
- Local ATF / OP-TEE OS patches: `patches/`

## SD Card Management

### Store Raspberry Pi Image from SD Card

```bash
# List all disks to identify your SD card
diskutil list

# Unmount the SD card (replace /dev/disk6 with your device)
diskutil unmountDisk /dev/disk6

# Backup the SD card to an image file
sudo dd if=/dev/disk6 of="$HOME/rpi5-optee.img" bs=4m status=progress
sync

# Verify the image was created
ls -lh "$HOME/rpi5-optee.img"

# Compress the image (optional)
gzip -9 "$HOME/rpi5-optee.img"
```

### Flush Raspberry Pi Image to SD Card

```bash
# List all disks to identify your SD card
diskutil list

# Unmount the SD card (replace /dev/disk6 with your device)
diskutil unmountDisk /dev/disk6

# Write the image to the SD card
sudo dd if="$HOME/rpi5-optee.img" of=/dev/disk6 bs=4m status=progress
sync

# Eject the SD card
diskutil eject /dev/disk6
```

## Environment Setup

### Prerequisites

- Raspberry Pi 5 running 64-bit Raspberry Pi OS (Debian 13 Trixie or later)
- Network connectivity via Ethernet (recommended for initial setup) or WiFi
- SSH access to the Raspberry Pi

### Initial Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/sajibmitra/optee-rpi5.git
   cd optee-rpi5
   ```

2. **Set up SSH key authentication:**
   ```bash
   # Copy your public SSH key to the Raspberry Pi
   # Default credentials: username=skmitra, password=test!26
   ssh-copy-id skmitra@172.20.10.2  # Replace with your Pi's LAN IP
   ```

3. **Configure environment variables:**
   ```bash
   export PI_SUDO_PASSWORD='testP!26'
   ```

4. **Monitor the secure world (optional):**
   ```bash
   # Run in one terminal to monitor OP-TEE secure world
   ./monitoring_rpi5_optee_secure_world.sh skmitra@172.20.10.2
   
   # Run tests in another terminal
   ./monitoring_rpi5_optee_secure_world.sh skmitra@172.20.10.2 -- xtest -l 0
   # SEC = secure world, NW = Normal World
   ```

## Frequently Asked Questions

### What distribution does OP-TEE run on?

The base system is **64-bit Raspberry Pi OS** (based on Debian 13 Trixie), not Raspbian (which is 32-bit). After installing OP-TEE, the system becomes **Raspberry Pi OS Debian with OP-TEE**.

This environment includes:
- **TF-A (ARM Trusted Firmware)** - boot stage
- **OP-TEE OS** - secure world execution
- **Linux kernel** - normal world
- **Debian rootfs** - userspace

### Do your scripts require network connectivity?

Yes. The scripts install OP-TEE on a remote Raspberry Pi device over a network connection. **Ethernet (LAN) is recommended** for initial setup to ensure stable connectivity. Once the environment is fully built, you can use WiFi for subsequent operations.

### What is PI_LAN_IP?

`PI_LAN_IP` is the local network IP address assigned to your Raspberry Pi. Make sure your Raspberry Pi is connected to your local network (via Ethernet or WiFi) and that you know its IP address before running deployment scripts.

### What modifications are needed in config.txt?

The `/boot/firmware/config.txt` file requires these settings for OP-TEE to work:

```
[all]
enable_uart=1
armstub=armstub8-2712-optee.bin
kernel_address=0x200000
```

### Should I enable dtoverlay=optee-rpi5?

No. Do **not** enable `dtoverlay=optee-rpi5` when `CFG_DT=y`. This configuration is handled automatically by the build system.

## Notes

- Required `config.txt`: `armstub=armstub8-2712-optee.bin`, `kernel_address=0x200000`
- Do **not** enable `dtoverlay=optee-rpi5` when CFG_DT=y
- Kernel source cache (`.cache/linux-rpi`) is **not** in this repo; scripts fetch/build it locally
- Default Raspberry Pi credentials: `username=skmitra`, `password=test!26`, `sudo password=testP!26`
