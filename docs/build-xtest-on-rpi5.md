# Building and Verifying `xtest` on Raspberry Pi 5

This document explains what the monitoring script does with `xtest`, how `xtest`
is built and deployed today, and how to **build `xtest` on the Pi 5 from source**
to demonstrate on-device self-building availability.

## What the monitoring script does

`monitoring_rpi5_optee_secure_world.sh` SSHes to the Pi and runs **`xtest`**
(not "xtext") in normal world while streaming secure-world logs. The default
remote command is:

```bash
xtest -l 0
```

Example:

```bash
./monitoring_rpi5_optee_secure_world.sh skmitra@172.20.10.2 -- xtest -l 0
```

The script does **not** build anything. It runs whatever `xtest` `sudo` finds
on the Pi (typically `/usr/local/bin/xtest` after deploy).

## How `xtest` is built today (not on the Pi)

In `build-rpi5-optee.sh`, the flow is:

1. Build `optee_os` (cross-compiled with `aarch64-linux-gnu-`)
2. Build `optee_client` and `optee_test` with `CROSS_COMPILE=` on the **build host**
3. Copy the result into the deploy overlay at `/usr/local/bin/xtest`

`deploy-rpi5-optee.sh` then copies `rootfs-overlay/usr/` to the Pi
(`/usr/local/bin/xtest`, TAs under `/lib/optee_armtz/`, plugins, etc.).

So: **a successful monitoring run proves deployed `xtest` works on RP5, but it
does not prove RP5 built `xtest` from source itself.**

To show self-building availability, you need a separate **on-Pi build + run**
step.

---

## Verification checklist

### 1. Confirm the running binary is the deployed one

On the Pi:

```bash
which xtest
ls -l /usr/local/bin/xtest
file /usr/local/bin/xtest
md5sum /usr/local/bin/xtest
```

You should see an AArch64 ELF under `/usr/local/bin/`.

### 2. Build `xtest` on the Pi from source

You need three things on the Pi:

| Requirement | Purpose |
|---|---|
| `optee_test` source | Host app + regression TAs |
| `TA_DEV_KIT_DIR` | From `optee_os/out/arm-plat-rpi5/export-ta_arm64` |
| `OPTEE_CLIENT_EXPORT` | Headers/libs from `optee_client` (or installed `libteec`) |

**Easiest path:** copy the dev-kit and client export from your build host
(already produced by `build-rpi5-optee.sh`), then build natively on the Pi.

On the **build host**:

```bash
cd ~/optee/pi5-optee
tar czf /tmp/optee-onpi-build-deps.tgz \
  optee_test \
  optee_os/out/arm-plat-rpi5/export-ta_arm64 \
  optee_client/out/export/usr
scp /tmp/optee-onpi-build-deps.tgz skmitra@172.20.10.2:/tmp/
```

On the **Pi**:

```bash
sudo apt update
sudo apt install -y git build-essential python3 python3-pyelftools \
  device-tree-compiler libssl-dev

mkdir -p ~/optee-onpi-build && cd ~/optee-onpi-build
tar xzf /tmp/optee-onpi-build-deps.tgz

export TA_DEV_KIT_DIR="$PWD/optee_os/out/arm-plat-rpi5/export-ta_arm64"
export OPTEE_CLIENT_EXPORT="$PWD/optee_client/out/export/usr"

# If you only unpacked export dirs, adjust paths to where they landed:
# export TA_DEV_KIT_DIR="$PWD/export-ta_arm64"
# export OPTEE_CLIENT_EXPORT="$PWD/usr"

make -C optee_test \
  CROSS_COMPILE= \
  TA_DEV_KIT_DIR="$TA_DEV_KIT_DIR" \
  OPTEE_CLIENT_EXPORT="$OPTEE_CLIENT_EXPORT" \
  -j"$(nproc)"
```

Install the locally built artifacts (separate from the deployed copy, for a
clean proof):

```bash
sudo make -C optee_test \
  CROSS_COMPILE= \
  TA_DEV_KIT_DIR="$TA_DEV_KIT_DIR" \
  OPTEE_CLIENT_EXPORT="$OPTEE_CLIENT_EXPORT" \
  DESTDIR=/opt/xtest-selfbuilt \
  bindir=/usr/local/bin \
  install

# TAs + plugin (needed for full xtest, e.g. regression 1033)
sudo mkdir -p /opt/xtest-selfbuilt/lib/optee_armtz
sudo cp optee_test/out/ta/*.ta /opt/xtest-selfbuilt/lib/optee_armtz/ 2>/dev/null || \
  sudo cp optee_test/out/ta/*/*.ta /opt/xtest-selfbuilt/lib/optee_armtz/
sudo mkdir -p /opt/xtest-selfbuilt/usr/lib/tee-supplicant/plugins
sudo cp optee_test/out/supp_plugin/*.plugin /opt/xtest-selfbuilt/usr/lib/tee-supplicant/plugins/
```

Or install over system paths if you intend to replace the deployed binary:

```bash
sudo cp optee_test/out/xtest/xtest /usr/local/bin/xtest.selfbuilt
sudo cp optee_test/out/ta/*/*.ta /lib/optee_armtz/
sudo cp optee_test/out/supp_plugin/*.plugin /usr/lib/tee-supplicant/plugins/
sudo systemctl restart tee-supplicant || sudo tee-supplicant &
```

### 3. Prove it was self-built

```bash
# Different hash from pre-deployed binary
md5sum /usr/local/bin/xtest /usr/local/bin/xtest.selfbuilt

# Show build timestamp
ls -l --full-time optee_test/out/xtest/xtest
```

### 4. Run the monitoring script against the self-built binary

From the build host:

```bash
./monitoring_rpi5_optee_secure_world.sh skmitra@172.20.10.2 -- /usr/local/bin/xtest.selfbuilt -l 0
```

If that passes with `[NW]` and `[SEC]` output like a normal run, you have
demonstrated:

- `xtest` was **compiled on RP5**
- it **runs correctly** against your OP-TEE stack
- the monitoring workflow still works with the self-built binary

---

## What to document for reviewers

For "self-building availability," capture:

1. Pi model + OS/kernel (`uname -a`, `/etc/os-release`)
2. Build commands run **on the Pi** (not `build-rpi5-optee.sh` on host)
3. `file` / `md5sum` of old vs new `xtest`
4. Monitoring script output for `xtest -l 0` using the self-built path
5. Note that TAs/plugins were also rebuilt on-Pi (full source build, not just
   copying the host binary)

---

## Important nuance

The host script `build-rpi5-optee.sh` already builds `optee_client` and
`optee_test` with `CROSS_COMPILE=` (native on the build machine), then
**deploys** to the Pi. That is "build from source," but **off-device**.

Building on RP5 specifically means running `make -C optee_test ...` on the Pi
and then passing the resulting binary to the monitoring script. That is the
evidence that matters for on-device self-building availability.
