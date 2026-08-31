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

## Notes

- Required `config.txt`: `armstub=armstub8-2712-optee.bin`, `kernel_address=0x200000`
- Do **not** enable `dtoverlay=optee-rpi5` when CFG_DT=y
- Kernel source cache (`.cache/linux-rpi`) is **not** in this repo; scripts fetch/build it locally
