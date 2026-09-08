# QAI-OPTEE Running Manual (Raspberry Pi 5)

Complete guide to **build, deploy, and run** the Hybrid QAI Trusted Application
(`qai_ta`) on a Raspberry Pi 5 with real OP-TEE.

Related docs:

- Roadmap: [`qai-optee-prototype-roadmap.md`](qai-optee-prototype-roadmap.md)
- Architecture: [`qai-optee-architecture.md`](qai-optee-architecture.md)
- Example README: [`../optee_examples/qai_ta/README.md`](../optee_examples/qai_ta/README.md)
- Base OP-TEE platform: [`../README.md`](../README.md)

---

## 1. What this prototype does

Hybrid QAI keeps the Trusted Application small:

```text
Normal World (REE)                         Secure World (TEE / OP-TEE)
──────────────────                         ────────────────────────────
Sensor / features                          QAI TA
        │                                    │
        │  TEEC_InvokeCommand()              ├─ model parameters (resident)
        ├──────────────────────────────────► ├─ baseline / TinyML / QAI infer
        │                                    └─ optional decrypt (protected)
        │
Prediction + confidence ◄──────────────────┘
```

Demo input used throughout this manual:

```text
[10, 20, -5, 3]
```

Expected **baseline** result (first concrete milestone):

```text
Prediction : 1
Confidence : 28
```

---

## 2. Prerequisites

### 2.1 Hardware / platform

| Item | Requirement |
| ---- | ----------- |
| Board | Raspberry Pi 5 |
| OS | 64-bit Raspberry Pi OS with OP-TEE already deployed |
| Network | SSH LAN access to the Pi |
| Host | Linux build machine with `aarch64-linux-gnu-` toolchain |

OP-TEE must already be working (`xtest`, `/dev/tee0`, `tee-supplicant`).
If not, follow the main repo README first (`build-rpi5-optee.sh` /
`deploy_rpi5_optee_kernel.sh`).

### 2.2 Default Pi credentials (this project image)

| Field | Value |
| ----- | ----- |
| Username | `skmitra` |
| Login password | `test!26` |
| Sudo password | `testP!26` |

Example target used in this manual:

```bash
export PI_TARGET=skmitra@172.20.10.2
export PI_SUDO_PASSWORD='testP!26'
```

### 2.3 Host build dependencies

Already produced by a successful OP-TEE build in this repo:

```text
optee_os/out/arm-plat-rpi5/export-ta_arm64/     # TA_DEV_KIT_DIR
optee_client/out/export/usr/                   # TEEC_EXPORT (libteec)
aarch64-linux-gnu-gcc                          # CROSS_COMPILE
```

Quick check on the **build host**:

```bash
cd ~/optee/pi5-optee
test -f optee_os/out/arm-plat-rpi5/export-ta_arm64/mk/ta_dev_kit.mk && echo TA_DEV_KIT_OK
test -d optee_client/out/export/usr/include && echo TEEC_OK
which aarch64-linux-gnu-gcc
```

Quick check on the **Pi**:

```bash
ssh "$PI_TARGET" 'uname -m; pgrep -a tee-supplicant; ls -l /dev/tee0; which xtest'
```

You should see `aarch64`, a running `tee-supplicant`, `/dev/tee0`, and `xtest`.

---

## 3. Source layout

```text
optee_examples/qai_ta/
├── host/
│   ├── main.c                 # REE client (qai_host)
│   └── Makefile
├── ta/
│   ├── qai_ta.c               # TA entry points + commands
│   ├── inference.c            # Secure inference kernels
│   ├── model_params.h         # TA-resident weights / θ / key
│   ├── user_ta_header_defines.h
│   ├── sub.mk
│   ├── Makefile
│   └── include/qai_ta.h
├── include/qai_ta.h           # Shared REE↔TEE ABI
├── tools/
│   ├── train_tinyml.py        # Offline TinyML training
│   └── train_qai_hybrid.py    # Offline quantum-inspired training
├── scripts/
│   ├── build-qai-ta.sh        # Cross-build host + TA
│   ├── deploy-qai-ta.sh       # SCP + install on Pi
│   └── measure.sh             # Latency sweep helper
├── CMakeLists.txt
├── Makefile
└── README.md
```

Installed on the Pi after deploy:

| Artifact | Path |
| -------- | ---- |
| Client | `/usr/local/bin/qai_host` |
| Trusted Application | `/lib/optee_armtz/24173bc2-5143-4d91-92c5-ffae31dc618d.ta` |

UUID: `24173bc2-5143-4d91-92c5-ffae31dc618d`

---

## 4. Build on the host

From the repo root:

```bash
cd ~/optee/pi5-optee
./optee_examples/qai_ta/scripts/build-qai-ta.sh
```

What the script sets:

```bash
TA_DEV_KIT_DIR=$PWD/optee_os/out/arm-plat-rpi5/export-ta_arm64
TEEC_EXPORT=$PWD/optee_client/out/export/usr
CROSS_COMPILE=aarch64-linux-gnu-
```

Expected outputs:

```text
optee_examples/qai_ta/out/ca/qai_host
optee_examples/qai_ta/out/ta/24173bc2-5143-4d91-92c5-ffae31dc618d.ta
```

Verify:

```bash
file optee_examples/qai_ta/out/ca/qai_host
# ELF 64-bit LSB ... ARM aarch64 ...
ls -lh optee_examples/qai_ta/out/ta/*.ta
```

### Manual build (equivalent)

```bash
cd ~/optee/pi5-optee/optee_examples/qai_ta
make clean || true
make \
  CROSS_COMPILE=aarch64-linux-gnu- \
  TA_DEV_KIT_DIR="$PWD/../../optee_os/out/arm-plat-rpi5/export-ta_arm64" \
  TEEC_EXPORT="$PWD/../../optee_client/out/export/usr" \
  -j"$(nproc)"
```

---

## 5. Deploy to the Raspberry Pi 5

### 5.1 Recommended non-interactive deploy

The helper script uses interactive `sudo` over SSH. On this image,
`/dev/tee0` is root-owned (`crw-------`), and install also needs root.
Use the following reliable method:

```bash
cd ~/optee/pi5-optee
export PI_TARGET=skmitra@172.20.10.2
export PI_SUDO_PASSWORD='testP!26'

OUT=~/optee/pi5-optee/optee_examples/qai_ta/out
TA=24173bc2-5143-4d91-92c5-ffae31dc618d.ta

scp "$OUT/ca/qai_host" "$PI_TARGET:/tmp/qai_host"
scp "$OUT/ta/$TA" "$PI_TARGET:/tmp/$TA"

ssh "$PI_TARGET" bash -s <<EOF
set -e
PASS='$PI_SUDO_PASSWORD'
printf '%s\n' "\$PASS" | sudo -S -p '' install -m 0755 /tmp/qai_host /usr/local/bin/qai_host
printf '%s\n' "\$PASS" | sudo -S -p '' install -m 0644 /tmp/$TA /lib/optee_armtz/$TA
printf '%s\n' "\$PASS" | sudo -S -p '' systemctl restart tee-supplicant 2>/dev/null || true
ls -l /usr/local/bin/qai_host /lib/optee_armtz/$TA
pgrep -a tee-supplicant
EOF
```

### 5.2 Helper script (interactive sudo)

```bash

~/optee/pi5-optee/optee_examples/qai_ta/scripts/deploy-qai-ta.sh skmitra@172.20.10.2
```

You may be prompted for the Pi sudo password.

### 5.3 Confirm install

```bash
ssh "$PI_TARGET" 'ls -l /usr/local/bin/qai_host /lib/optee_armtz/24173bc2-5143-4d91-92c5-ffae31dc618d.ta'
```

---

## 6. Run on the Pi

### 6.1 Important: use `sudo`

On the validated image, `/dev/tee0` is mode `600` root:root. Running as a
normal user fails with:

```text
TEEC_InitializeContext failed 0xffff0008
```

(`0xffff0008` = `TEEC_ERROR_ITEM_NOT_FOUND` when the TEE device cannot be opened.)

Always run:

```bash
sudo qai_host ...
```

Same requirement as `sudo xtest`.

### 6.2 Baseline (Phases 2–4) — first milestone

On the Pi:

```bash
sudo qai_host
```

Expected output shape:

```text
================================
 QAI-OPTEE Raspberry Pi 5 Test
================================

Input:
  [10, 20, -5, 3]

Sending data to OP-TEE...

Prediction : 1
Confidence : 28
Score      : 28
Model      : baseline

TEE execution time : xxxxx us
```

Validated on physical Pi 5 (`skmitra@172.20.10.2`): **Prediction 1**,
**Confidence 28**, TEE time about **10–11 ms**.

### 6.3 TinyML (Phases 5 / 7)

```bash
sudo qai_host --tinyml
```

Uses logistic-regression weights resident in the TA (`model_params.h`).
Example validated result: Prediction `1`, Confidence `22`.

### 6.4 Quantum-inspired QAI (Phases 6 / 9)

```bash
sudo qai_host --qai
```

Uses θ / γ pairwise hybrid parameters in the TA.
Example validated result: Prediction `1`, Confidence `5`.

### 6.5 Protected path (Phase 8)

Normal World encrypts features (XOR with shared prototype key). The TA
decrypts, runs inference, and returns only the result.

```bash
sudo qai_host --protected --qai
# also valid:
sudo qai_host --protected --tinyml
sudo qai_host --protected --baseline
```

Example validated result: Prediction `1`, Confidence `5`, Model `qai (protected)`.

### 6.6 Model / TA info

```bash
sudo qai_host --info
```

Example:

```text
TA version           : 1
Feature count        : 4
Baseline params      : 20 bytes
TinyML params        : 20 bytes
QAI params           : 36 bytes
TA stack hint        : 4096 bytes
TA heap hint         : 32768 bytes
```

### 6.7 REE vs TEE comparison (Phase 9)

Single-shot side-by-side:

```bash
sudo qai_host --ree-compare
```

Averaged latency (also runs a REE software baseline for comparison):

```bash
sudo qai_host --bench 50
sudo qai_host --bench 200 --tinyml
sudo qai_host --bench 200 --qai
sudo qai_host --protected --qai --bench 200
```

Example validated (`--bench 50`, baseline):

```text
TEE avg inference : 10850 us
REE avg inference : 0 us
Last prediction   : 1 (conf 28)
```

> Note: REE-only integer inference is extremely cheap; average may round to
> `0 us` with `CLOCK_MONOTONIC` microsecond resolution. Prefer larger `N`,
> or report TEE wall time as the primary OP-TEE overhead metric.

### 6.8 Full measurement sweep

Copy or run `measure.sh` on the Pi (after installing `qai_host`):

```bash
# from host, after deploy:
scp optee_examples/qai_ta/scripts/measure.sh "$PI_TARGET:/tmp/measure-qai.sh"
ssh "$PI_TARGET" "chmod +x /tmp/measure-qai.sh && sudo QAI_HOST=qai_host /tmp/measure-qai.sh 200"
```

Or invoke the four benches manually with `sudo` as in §6.7.

### 6.9 Command cheat sheet

| Command | Meaning |
| ------- | ------- |
| `sudo qai_host` | Baseline weighted C model |
| `sudo qai_host --baseline` | Same as default |
| `sudo qai_host --tinyml` | TinyML logistic inference in TEE |
| `sudo qai_host --qai` | Quantum-inspired hybrid inference |
| `sudo qai_host --protected [--tinyml\|--qai\|--baseline]` | Encrypt in REE, decrypt+infer in TEE |
| `sudo qai_host --info` | Parameter / stack / heap hints |
| `sudo qai_host --ree-compare` | Print REE then TEE results |
| `sudo qai_host --bench N` | Average TEE (+ REE) latency over N runs |
| `sudo qai_host --help` | Usage |

---

## 7. Monitor Secure World logs (optional)

In one terminal on the host:

```bash
./monitoring_rpi5_optee_secure_world.sh skmitra@172.20.10.2
```

In another:

```bash
ssh -t skmitra@172.20.10.2 'sudo qai_host'
```

You should see TA messages such as:

```text
[TEE] QAI TA session opened
[TEE] QAI inference started
[TEE] Input validated (4 features)
[TEE] Inference completed pred=1 conf=28
```

(`IMSG` / `DMSG` visibility depends on OP-TEE log level.)

---

## 8. Retrain model parameters (host / Mac)

Do **not** train inside the TA. Train offline, then embed compact integers.

```bash
cd ~/optee/pi5-optee/optee_examples/qai_ta

python3 tools/train_tinyml.py
python3 tools/train_qai_hybrid.py
```

Each script prints a C snippet. Paste into `ta/model_params.h`
(and mirror the same constants in `host/main.c` REE baseline arrays if you
want fair REE↔TEE numeric comparison). Then rebuild and redeploy:

```bash
./scripts/build-qai-ta.sh
# then deploy again (Section 5)
```

---

## 9. End-to-end checklist

```text
[ ] OP-TEE running on Pi (tee-supplicant, /dev/tee0, xtest OK)
[ ] Host has TA_DEV_KIT_DIR + TEEC_EXPORT + aarch64 toolchain
[ ] ./optee_examples/qai_ta/scripts/build-qai-ta.sh succeeds
[ ] qai_host + .ta copied to Pi and installed under /usr/local/bin and /lib/optee_armtz
[ ] sudo qai_host            → Prediction 1, Confidence 28
[ ] sudo qai_host --tinyml   → runs
[ ] sudo qai_host --qai      → runs
[ ] sudo qai_host --protected --qai → runs
[ ] sudo qai_host --info     → shows param sizes
[ ] sudo qai_host --bench 50 → prints TEE avg µs
```

---

## 10. Troubleshooting

| Symptom | Likely cause | Fix |
| ------- | ------------ | --- |
| `TEEC_InitializeContext failed 0xffff0008` | Cannot open `/dev/tee0` (permissions) | Run with `sudo qai_host` |
| `TEEC_OpenSession failed` / TA not found | `.ta` not installed or wrong UUID path | Re-copy TA to `/lib/optee_armtz/24173bc2-5143-4d91-92c5-ffae31dc618d.ta`; restart `tee-supplicant` |
| `TEEC_InvokeCommand failed` | Bad params / ABI mismatch | Rebuild host + TA together and redeploy both |
| `TA_DEV_KIT_DIR missing` on build | OP-TEE OS not built | Run `./build-rpi5-optee.sh` first |
| `cannot find -lteec` | Client export missing | Ensure `optee_client/out/export/usr` exists |
| No Secure World logs | Log level / UART not attached | Use `monitoring_rpi5_optee_secure_world.sh` |
| `sudo` password prompts over SSH | Interactive deploy | Use Section 5.1 with `PI_SUDO_PASSWORD` |
| SSH timeout | Wrong IP / Wi-Fi | Confirm Pi IP; try Ethernet; ping `172.20.10.2` |

Permission check:

```bash
ssh "$PI_TARGET" 'ls -l /dev/tee0 /dev/teepriv0'
# typical on this image:
# crw------- 1 root root ... /dev/tee0
```

Sanity-check OP-TEE independently:

```bash
ssh "$PI_TARGET" "printf '%s\n' '$PI_SUDO_PASSWORD' | sudo -S -p '' xtest 1001"
```

---

## 11. Security notes (research prototype)

- Model weights / θ / γ live only inside the TA binary (`model_params.h`).
- `--protected` demonstrates an encrypted-feature path; the current key is a
  **prototype XOR key** embedded for demo purposes, not production key
  management.
- For stronger protection later: TEE secure storage, AES via TEE Internal
  Crypto API, and attested model provisioning.

Core claim for papers / reports:

> Sensitive model parameters and (optionally) plaintext features are handled
> inside OP-TEE; the Normal World receives prediction and confidence only.

---

## 12. Quick copy-paste session

```bash
# --- on build host ---
cd ~/optee/pi5-optee
export PI_TARGET=skmitra@172.20.10.2
export PI_SUDO_PASSWORD='testP!26'

./optee_examples/qai_ta/scripts/build-qai-ta.sh

OUT=optee_examples/qai_ta/out
TA=24173bc2-5143-4d91-92c5-ffae31dc618d.ta
scp "$OUT/ca/qai_host" "$PI_TARGET:/tmp/qai_host"
scp "$OUT/ta/$TA" "$PI_TARGET:/tmp/$TA"
ssh "$PI_TARGET" "printf '%s\n' '$PI_SUDO_PASSWORD' | sudo -S -p '' install -m 0755 /tmp/qai_host /usr/local/bin/qai_host && \
  printf '%s\n' '$PI_SUDO_PASSWORD' | sudo -S -p '' install -m 0644 /tmp/$TA /lib/optee_armtz/$TA"

# --- run on Pi ---
ssh "$PI_TARGET" "printf '%s\n' '$PI_SUDO_PASSWORD' | sudo -S -p '' qai_host"
ssh "$PI_TARGET" "printf '%s\n' '$PI_SUDO_PASSWORD' | sudo -S -p '' qai_host --tinyml"
ssh "$PI_TARGET" "printf '%s\n' '$PI_SUDO_PASSWORD' | sudo -S -p '' qai_host --qai"
ssh "$PI_TARGET" "printf '%s\n' '$PI_SUDO_PASSWORD' | sudo -S -p '' qai_host --protected --qai"
ssh "$PI_TARGET" "printf '%s\n' '$PI_SUDO_PASSWORD' | sudo -S -p '' qai_host --bench 50"
ssh "$PI_TARGET" "printf '%s\n' '$PI_SUDO_PASSWORD' | sudo -S -p '' qai_host --info"
```

---

## 13. Validated reference result (physical Pi 5)

Environment: `skmitra@172.20.10.2`, OP-TEE 4.10, `tee-supplicant` running.

| Mode | Prediction | Confidence | Approx. TEE time |
| ---- | ---------- | ---------- | ---------------- |
| baseline | 1 | 28 | ~10875 µs |
| tinyml | 1 | 22 | ~10870 µs |
| qai | 1 | 5 | ~10789 µs |
| protected qai | 1 | 5 | ~7982 µs |
| bench 50 (baseline) | 1 | 28 | TEE avg ~10850 µs |
