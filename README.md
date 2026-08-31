# Raspberry Pi 5 real OP-TEE

Build, deploy, and test **real OP-TEE** on Raspberry Pi 5 (embedded armstub + custom OP-TEE kernel + LAN scripts).

## Quick start

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
