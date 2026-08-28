 # OP-TEE on Raspberry Pi 5
  Guide for preparing **Raspberry Pi OS** and installing **OP-TEE** on a
  **Raspberry Pi 5** (BCM2712).
  > **Educational use only.** The Pi 5 does not provide hardware-enforced secure
  DRAM isolation.
  ## Part 1 — Prepare Raspberry Pi OS
  ```bash
  cat /etc/rpi-issue && cat /etc/os-release && uname -r
  sudo apt update
  sudo apt install -y linux-image-rpi-2712 linux-headers-rpi-2712
  sudo apt full-upgrade
  sudo apt install -y git build-essential bc bison flex libssl-dev \
    device-tree-compiler python3 python3-pyelftools libfdt-dev swig \
    gcc-aarch64-linux-gnu
  export CROSS_COMPILE=aarch64-linux-gnu-
  ```
  Apt repos: `/etc/apt/sources.list.d/debian.sources` + `raspi.sources` (not
  `raspi.list`).
  Check kernel TEE support: `zcat /proc/config.gz | grep -E 'CONFIG_(TEE|OPTEE)'`
  ## Part 2 — Build OP-TEE OS
  ```bash
  export BASE_DIR=~/pi5-optee-build && mkdir -p "$BASE_DIR" && cd "$BASE_DIR"
  git clone https://github.com/OP-TEE/optee_os.git && cd optee_os
  make -j$(nproc) PLATFORM=rpi5 CFG_ARM64_core=y CFG_USER_TA_TARGETS=ta_arm64 \
    CFG_DT=y CFG_TEE_CORE_DEBUG=y CFG_TEE_CORE_LOG_LEVEL=3 CFG_CORE_ASLR=n
  export TA_DEV_KIT_DIR="$BASE_DIR/optee_os/out/arm-plat-rpi5/export-ta_arm64"
  ```
  ## Part 3 — Build TF-A + armstub
  ```bash
  cd "$BASE_DIR" && git clone
  https://github.com/ARM-software/arm-trusted-firmware.git
  cd arm-trusted-firmware && make -j$(nproc) PLAT=rpi5 SPD=opteed DEBUG=1
  cd "$BASE_DIR" && cp arm-trusted-firmware/build/rpi5/debug/bl31.bin
  bl31_bl32.bin
  dd if=optee_os/out/arm-plat-rpi5/core/tee-raw.bin of=bl31_bl32.bin bs=1024
  seek=512 conv=notrunc
  sudo cp /boot/firmware/armstub8-2712.bin /boot/firmware/armstub8-2712.bin.bak
  ```
  ## Part 4 — Device tree overlay
  ```bash
  cat > optee.dts << 'DTS'
  /dts-v1/;/plugin/;/ { compatible = "brcm,bcm2712","raspberrypi,5-model-b";
    fragment@0 { target-path = "/"; __overlay__ {
      optee { compatible = "linaro,optee-tz"; method = "smc"; }; }; }; };
  DTS
  dtc -@ -I dts -O dtb -o optee.dtbo optee.dts
  sudo cp optee.dtbo /boot/firmware/overlays/
  echo 'dtoverlay=optee' | sudo tee -a /boot/firmware/config.txt
  ```
  ## Part 5 — OP-TEE client
  ```bash
  cd "$BASE_DIR" && git clone https://github.com/OP-TEE/optee_client.git && cd
  optee_client
  make WITH_TEEACL=0 -j$(nproc)
  sudo cp -a out/export/usr/lib/libteec.so* /usr/lib/
  sudo cp out/export/usr/sbin/tee-supplicant /usr/sbin/
  sudo mkdir -p /data/tee && sudo tee-supplicant &
  ```
  ## Part 6 — Deploy
  ```bash
  sudo cp "$BASE_DIR/bl31_bl32.bin" /boot/firmware/armstub8-2712.bin
  sync && sudo reboot
  ```
  ## Part 7 — Verify
  ```bash
  dmesg | grep -i optee && ls -l /dev/tee*
  ```
  ## References
  - https://optee.readthedocs.io/
  - https://github.com/jonasjuffinger/OP-TEE-on-the-RPi-5
  - https://trustedfirmware-a.readthedocs.io/en/latest/plat/rpi5.html

