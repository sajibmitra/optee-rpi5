# OP-TEE on Raspberry Pi 5 — Deployment Guide
  Guide for preparing **Raspberry Pi OS** and installing **OP-TEE** on a
  **Raspberry Pi 5** (BCM2712).
  > **Educational use only.** The Pi 5 does not provide hardware-enforced secure
  DRAM isolation.
  This document describes **two ways** to deploy OP-TEE:
  | Method | When to use |
  |--------|-------------|
  | **[Method 1 — Scripts](#method-1--automated-deployment-using-scripts)** | Run
  helper scripts from `~/pi5-optee/` for a guided, repeatable install |
  | **[Method 2 — Manual steps](#method-2--manual-step-by-step-installation)** |
  Run each build and deploy command yourself for full control |
  ---
  ## Method 1 — Automated deployment using scripts
  All commands are run from the repository root **`~/pi5-optee/`** only. Do not
  run scripts from another directory.
  ### Clone the repository
  ```bash
  git clone <your-repo-url> ~/pi5-optee
  cd ~/pi5-optee
  ```
  ### One-time setup
  ```bash
  cd ~/pi5-optee
  chmod +x *.sh scripts/*.sh 2>/dev/null || true
  ls scripts/    # list actual script names in your repo
  ```
  Install dependencies (use the script name from your repo):
  ```bash
  ./scripts/install-deps.sh
  # or: ./setup-deps.sh
  ```
  ### Prepare Raspberry Pi OS (on the Pi)
  ```bash
  cd ~/pi5-optee
  ./scripts/prepare-os.sh
  ```
  This should match [Part 1](#part-1--prepare-raspberry-pi-os): kernel packages,
  build tools, and `CROSS_COMPILE`.
  ### Build OP-TEE
  **All-in-one:**
  ```bash
  cd ~/pi5-optee
  ./scripts/build-all.sh
  ```
  **Or step-by-step** (adjust names to match your `scripts/` folder):
  ```bash
  cd ~/pi5-optee
  ./scripts/build-optee-os.sh      # OP-TEE OS          → Part 2
  ./scripts/build-tfa-armstub.sh   # TF-A + armstub     → Part 3
  ./scripts/build-dt-overlay.sh    # Device tree overlay → Part 4
  ./scripts/build-optee-client.sh  # OP-TEE client      → Part 5
  ```
  ### Deploy and reboot
  ```bash
  cd ~/pi5-optee
  sudo ./scripts/deploy.sh
  # or: sudo ./scripts/install-optee.sh
  sync && sudo reboot
  ```
  ### Verify (after reboot)
  ```bash
  cd ~/pi5-optee
  ./scripts/verify-optee.sh
  ```
  Or manually:
  ```bash
  dmesg | grep -i optee && ls -l /dev/tee*
  ```
  ### Script workflow summary
  ```text
  ~/pi5-optee/
    │
    ├─ 1. cd ~/pi5-optee && chmod +x scripts/*.sh
    ├─ 2. ./scripts/install-deps.sh        (if present)
    ├─ 3. ./scripts/prepare-os.sh          (on the Pi)
    ├─ 4. ./scripts/build-all.sh           (or individual build-*.sh)
    ├─ 5. sudo ./scripts/deploy.sh
    └─ 6. ./scripts/verify-optee.sh        (after reboot)
  ```
  ---
  ## Method 2 — Manual step-by-step installation
  Run on the **Raspberry Pi 5** (native build) unless you are cross-compiling.
  ### Part 1 — Prepare Raspberry Pi OS
  ```bash
  cat /etc/rpi-issue && cat /etc/os-release && uname -r

  sudo apt update
  sudo apt install -y linux-image-rpi-2712 linux-headers-rpi-2712
  sudo apt full-upgrade

  sudo apt install -y git build-essential bc bison flex libssl-dev \
    device-tree-compiler python3 python3-pyelftools libfdt-dev swig \
    gcc-aarch64-linux-gnu

  export CROSS_COMPILE=aarch64-linux-gnu-

  **Apt sources:** `/etc/apt/sources.list.d/debian.sources` + `raspi.sources` (not
  legacy `raspi.list`).
  **Check kernel TEE support:**
  ```bash
  zcat /proc/config.gz | grep -E 'CONFIG_(TEE|OPTEE)'
  ```
  ---
  ### Part 2 — Build OP-TEE OS
  ```bash
  export BASE_DIR=~/pi5-optee-build && mkdir -p "$BASE_DIR" && cd "$BASE_DIR"

  git clone https://github.com/OP-TEE/optee_os.git && cd optee_os

  make -j$(nproc) PLATFORM=rpi5 CFG_ARM64_core=y CFG_USER_TA_TARGETS=ta_arm64 \
    CFG_DT=y CFG_TEE_CORE_DEBUG=y CFG_TEE_CORE_LOG_LEVEL=3 CFG_CORE_ASLR=n

  export TA_DEV_KIT_DIR="$BASE_DIR/optee_os/out/arm-plat-rpi5/export-ta_arm64"

  ---
  ### Part 3 — Build TF-A + armstub
  ```bash
  cd "$BASE_DIR" && git clone
  https://github.com/ARM-software/arm-trusted-firmware.git
  cd arm-trusted-firmware && make -j$(nproc) PLAT=rpi5 SPD=opteed DEBUG=1

  cd "$BASE_DIR"
  cp arm-trusted-firmware/build/rpi5/debug/bl31.bin bl31_bl32.bin

  dd if=optee_os/out/arm-plat-rpi5/core/tee-raw.bin of=bl31_bl32.bin bs=1024 \
    seek=512 conv=notrunc

  sudo cp /boot/firmware/armstub8-2712.bin /boot/firmware/armstub8-2712.bin.bak

  ---
  ### Part 4 — Device tree overlay
  ```bash
  cat > optee.dts << 'DTS'
  /dts-v1/;
  /plugin/;
  / {
    compatible = "brcm,bcm2712","raspberrypi,5-model-b";
    fragment@0 {
      target-path = "/";
      __overlay__ {
        optee {
          compatible = "linaro,optee-tz";
          method = "smc";
        };
      };
    };
  };
  DTS

  dtc -@ -I dts -O dtb -o optee.dtbo optee.dts
  sudo cp optee.dtbo /boot/firmware/overlays/
  echo 'dtoverlay=optee' | sudo tee -a /boot/firmware/config.txt

  ---
  ### Part 5 — OP-TEE client
  ```bash
  cd "$BASE_DIR" && git clone https://github.com/OP-TEE/optee_client.git && cd
  optee_client

  make WITH_TEEACL=0 -j$(nproc)

  sudo cp -a out/export/usr/lib/libteec.so* /usr/lib/
  sudo cp out/export/usr/sbin/tee-supplicant /usr/sbin/
  sudo mkdir -p /data/tee && sudo tee-supplicant &

  ---
  ### Part 6 — Deploy
  ```bash
  sudo cp "$BASE_DIR/bl31_bl32.bin" /boot/firmware/armstub8-2712.bin
  sync && sudo reboot
  ```
  ---
  ### Part 7 — Verify
  After reboot:
  ```bash
  dmesg | grep -i optee && ls -l /dev/tee*
  ```
  Expected: OP-TEE lines in `dmesg` and devices such as `/dev/tee0`,
  `/dev/teepriv0`.
  ---
  ## Comparison
  | Step | Method 1 (scripts in `~/pi5-optee/`) | Method 2 (manual) |
  |------|--------------------------------------|-------------------|
  | OS prep | `./scripts/prepare-os.sh` | Part 1 |
  | OP-TEE OS | `./scripts/build-optee-os.sh` | Part 2 |
  | TF-A / armstub | `./scripts/build-tfa-armstub.sh` | Part 3 |
  | DT overlay | `./scripts/build-dt-overlay.sh` | Part 4 |
  | Client | `./scripts/build-optee-client.sh` | Part 5 |
  | Install + reboot | `sudo ./scripts/deploy.sh` | Part 6 |
  | Verify | `./scripts/verify-optee.sh` | Part 7 |
  ---
  ## References
  - [OP-TEE documentation](https://optee.readthedocs.io/)
  - [OP-TEE on the RPi 5
  (jonasjuffinger)](https://github.com/jonasjuffinger/OP-TEE-on-the-RPi-5)
  - [TF-A RPi5 platform
  guide](https://trustedfirmware-a.readthedocs.io/en/latest/plat/rpi5.html)
