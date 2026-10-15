# Secure-world analysis: HAI fidelity kernel on the Pi 5 TA

Companion numbers:
[`hai-qhsvm-pi5-tee-resource-estimate-arXiv_2409.04935.md`](hai-qhsvm-pi5-tee-resource-estimate-arXiv_2409.04935.md).

The Normal World NumPy run is a different experiment:
[`hai-qhsvm-pi5-resource-analysis-arXiv_2409.04935.md`](hai-qhsvm-pi5-resource-analysis-arXiv_2409.04935.md).

This note records how the secure-world numbers were taken, and what they
mean for training, inference, and hardware. The board has no quantum
processor. The paper’s HAI table is a noiseless classical simulation. The
measurement here is that simulation again, moved into the OP-TEE Trusted
Application and timed with the TEE clock.

---

## 1. Procedure

### 1.1 Confirm the secure world was actually there

On 15 October 2026, SSH to `skmitra@172.20.10.2` showed:

- `/dev/tee0` and `/dev/teepriv0` present, mode `crw------- root:root`
- `/usr/sbin/tee-supplicant` running
- `/usr/local/bin/xtest` and `/usr/local/bin/qai_host` installed
- `/lib/optee_armtz/24173bc2-5143-4d91-92c5-ffae31dc618d.ta` already installed

`qai_host` as user `skmitra` failed with `TEEC_InitializeContext` error
`0xffff0008` (`TEEC_ERROR_ITEM_NOT_FOUND`), because that user cannot open
`/dev/tee0`. The same binary as root opened a session and `qai_host --info`
returned the TA metadata. Every timing command below ran as root for that
reason.

### 1.2 What the already-deployed TA was

Before any new command, `qai_host --info` reported:

| Field | Value |
|---|---|
| TA version | 1 |
| Feature count | 4 |
| QAI parameter bytes | 36 |
| Stack hint | 4,096 |
| Heap hint | 32,768 |

`qai_host --qai --bench 500` reported **TEE avg inference 10,758 µs** and
**REE avg inference 0 µs**. That command is `qai_infer_qai`: a few `int64`
multiply-adds on four features. The host prints a line on every call, and
the TA logs with `IMSG` on every call. The 10.8 ms is that whole invoke, not
an 8-qubit circuit. The REE average prints as 0 µs because those integer
operations finish in well under 1 µs and the average is integer division.
This path was measured so it would not be mistaken for the HAI kernel. It
was measured again after the new TA was installed (`--qai --bench 50`) and
still printed **10,757 µs**.

### 1.3 Code that actually ran in the TA

`CFG_TA_FLOAT_SUPPORT=y` in
`optee_os/out/arm-plat-rpi5/export-ta_arm64/mk/conf.mk`, so a user TA on this
build may use floating point. The secure kernel saves VFP state for that
configuration. The TA is still compiled as a normal OP-TEE user TA: no GPU
API, no quantum API.

Added pieces, then cross-built with
`optee_examples/qai_ta/scripts/build-qai-ta.sh` and installed over the
existing UUID:

- `optee_examples/qai_ta/ta/fidelity_kernel.c`
- command `TA_QAI_CMD_BENCH_FIDELITY` (id 5)
- host flag `qai_host --kernel-bench N`

The circuit is the one described in Sections II and IV of arXiv:2409.04935
and used for the Normal World NumPy timing:

1. Statevector of \(2^8 = 256\) amplitudes, stored in the TA `.bss`, not on
   the 4 KiB stack.
2. Three layers. Each layer applies `RY` and `RZ` from a pair of features on
   every qubit, a ring of eight CNOTs, then the same `RY`/`RZ` pair again.
3. The inverse for the second vector: negated angles, gates in reverse order,
   CNOT ring walked backwards.
4. \(k_p = \exp(\lvert a_0\rvert^2)\).

`sin` and `cos` are polynomials in the TA so the link does not pull in glibc
`libm`. The inverse uses the same functions, so a vector compared with itself
must come back to \(\lvert 0\rangle\) if the gate order is right. The TA
returned 2,718,281 × 10⁻⁶. \(e \times 10^{6} = 2718281.828\ldots\), and the
value is stored with a cast to `int64`, which truncates. The printed
“expect 2718282” on the binary that was timed was a rounding label in the
host string. The returned integer is the truncation of \(e\), which is the
passing self-check.

Random angles in \([-\pi,\pi]\) are produced by an LCG inside the TA. The
HAI CSV is not on the board. After features are in that range, every sample
executes the same gate count, so the kernel time does not depend on the
original sensor values.

One invoke does every evaluation inside the TA. The host does not enter the
TEE once per kernel. `TEE_GetSystemTime` is read immediately before the loop
and immediately after it. There is no `IMSG` inside the loop. The host’s
`CLOCK_MONOTONIC` interval wraps that single `TEEC_InvokeCommand`.

The signed TA installed on the board is 85,152 bytes. `tee-supplicant` was
restarted after install so the new blob was the one opened.

### 1.4 Runs

1. `--kernel-bench 20` as a smoke test. 8 ms on the TEE clock is only eight
   ticks, so that rate was not used.
2. `--kernel-bench 8000`, twice. 2,116 ms and 2,096 ms.
3. `--kernel-bench 20000`, with `vcgencmd pmic_read_adc` and `/proc/stat`
   sampled from Linux while the command ran. **5,246 ms**, **3,812.4
   kernels/s**. This is the rate in the estimate. Linux showed 25% CPU, so
   one core was busy. Mean rail power on the seven samples taken during the
   loop was **3.114 W**. The sample after the process had exited (3.3% CPU,
   2.12 W) was not included in that mean.
4. Ten times `--kernel-bench 1`, to see the cost of entering the TA when the
   batch does not hide it. Warm invokes were about 0.59 ms of REE wall for
   the self-check plus one kernel. The TEE clock, which steps by 1 ms,
   reported 0 or 1 and cannot price a single kernel.

No second TA session was started. Four-core scaling from the Normal World
note does not apply here and is not claimed.

### 1.5 How the HAI totals were computed

\[
T = 637200 / 3812.4 = 167.1\,\mathrm{s}
\]

for one classified row against every second of the 177-hour training file.
Energy uses the measured rail power of that one-core run,
\(167.1 \times 3.114\,\mathrm{W} = 0.144\,\mathrm{Wh}\).

The full test file is \(442800 \times 637200\) circuits at the same rate:
**2.35 years** of one secure core. The dense matrix is still 2,102 GiB and
was not allocated in the TA.

---

## 2. Hardware the secure run used

| Hardware | Used for this measurement? |
|---|---|
| Cortex-A76, one core, Secure World via OP-TEE | Yes |
| The other three cores | No. Utilisation stayed at 25% |
| GPU | No |
| NPU or other accelerator | No |
| Quantum processor | No. The statevector never left the CPU |

Floating point in the TA is a software configuration of this OP-TEE build
(`CFG_TA_FLOAT_SUPPORT`), not an extra chip.

The integer QAI command that was already in the TA also needs none of those
devices. It is not the HAI classifier. Training for that small model remains
`tools/train_qai_hybrid.py` on the development host.

---

## 3. Training and inference, in the secure world

### Training

Training of the paper’s one-class SVM was **not** run inside the TA. A
training kernel is one fidelity evaluation per pair of training rows. At
3,812 evaluations per second, a full \(637200 \times 637200\) Gram matrix is
not a TA workload: the matrix is thousands of gigabytes, and the pair count
is far above the 2.35-year test-time figure. The paper does not say it
trained on every second of the 177 hours. Whatever subset is used, each pair
can be the same TA command that was timed. The SVM solver itself
(scikit-learn in the paper) stays in the Normal World. Nothing in this run
sends a circuit to a quantum processor, and nothing requires a GPU.

### Inference

Inference of one new 16-feature vector, as the paper’s test step describes
it, is one fidelity against each training row that is still required, then a
dot product with the dual coefficients.

The fidelity half now has a measured secure-world cost: **0.262 ms per
training row**, **167 s** against the full 177-hour file, inside one TA
invocation so the world switch is paid once. Doing one `InvokeCommand` per
training row would add the entry cost seen in the single-eval calls (a few
tenths of a millisecond of REE wall once warm) on top of each 0.262 ms
kernel. The batch command avoids that.

The dot product and the classical preprocessing were not moved into the TA.
Preprocessing remains a few seconds for a whole HAI file in the Normal World.
The dot product is negligible next to 167 s of circuits.

So yes: this inference kernel runs on the target device using only its CPU,
and the CPU time below is time spent in the Trusted Application. It does not
need a quantum processor to do so. It also does not keep up with HAI’s
1 sample/second if every historical training second is a kernel column.
About 3,800 columns fit in that one second on this TA.

### What is still the small QAI prototype

`qai_infer_qai` is unchanged: four features, integer \(\theta\) and \(\gamma\),
score in Secure World. Its `--bench` time of about 10.8 ms per call is
dominated by per-call logging, which the fidelity loop does not do. Using
that 10.8 ms as the cost of the HAI circuit would overstate the circuit and
describe the wrong program.

---

## 4. Short answers

1. The secure-world rate is 20,000 fidelity evaluations in 5,246 ms of
   `TEE_GetSystemTime`, one core, 3.11 W rail power, TA image about 116 KiB.
   One HAI row against the full training file is 167 s inside that TA.
2. The run did not use a GPU, an accelerator, or a quantum processor.
3. Training of the paper’s SVM was not executed in the TA. Inference of the
   fidelity kernel was. It runs on this Pi’s CPU in Secure World. The
   separate four-feature QAI command also runs on that CPU and is not this
   measurement.
