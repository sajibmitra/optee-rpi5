# Secure-world RAM and CPU estimate: HAI fidelity kernel

Measured on the Raspberry Pi 5 at `skmitra@172.20.10.2` with the 8-qubit
fidelity kernel running **inside the OP-TEE Trusted Application**
`24173bc2-5143-4d91-92c5-ffae31dc618d`. The clock is `TEE_GetSystemTime`
around the circuit loop. The Normal World only starts that one command
(`qai_host --kernel-bench`) and reads the result back.

This is the secure-world counterpart of
[`hai-qhsvm-pi5-resource-estimate-arXiv_2409.04935.md`](hai-qhsvm-pi5-resource-estimate-arXiv_2409.04935.md).
That earlier file is a Normal World NumPy process. It is not reused as a
TEE number here.

Paper: Cultice et al., arXiv:2409.04935v1, local copy
[`2409.04935v1.pdf`](2409.04935v1.pdf).

There is still no quantum processor. The TA evaluates the circuit as
ordinary floating-point code on one Cortex-A76, in Secure World, because
`CFG_TA_FLOAT_SUPPORT=y` on this OP-TEE build.

---

## 1. Result

Classifying **one** HAI sample against the full 177-hour training file
(637,200 rows), using the measured in-TA rate:

| Resource | Secure-world measurement |
|---|---|
| CPU time | **167 s (2.8 min)** on the one core that entered the TA |
| Secure memory for the loaded TA | **about 116 KiB** (ELF sections plus the 4 KiB stack). The 4.9 MiB kernel row, if kept, sits in the Normal World |
| Board rail power during the run | **3.11 W** average on that one core (samples while the TA was busy) |
| Energy for that one classification | **0.14 Wh** at 3.11 W |

The TA ran at **3,812 kernels/s** (0.262 ms each). A 1-second HAI sample can
absorb about **3,800 training rows** before the next sample arrives. The full
training file is about **167×** that budget.

The whole 123-hour test file against the full training file is
\(442800 \times 637200\) kernel evaluations: **2.35 years** on this one
secure core. Four-core TEE speedup was **not** measured. Linux reported
about 25% CPU while the command ran, which is one of the four cores.

The same circuit in Normal World NumPy took 3.95 ms and 42 minutes per
sample. The TA is the same gate schedule in C, so the kernel itself is
faster. The world switch is not the dominant cost once many kernels share
one `TEEC_InvokeCommand`.

---

## 2. What was timed

Command inside the TA: `TA_QAI_CMD_BENCH_FIDELITY`, implemented in
`optee_examples/qai_ta/ta/fidelity_kernel.c`.

Schedule, matching the Normal World measurement and Sections II and IV of
the paper:

- 16 features, 8 qubits, statevector of 256 complex amplitudes.
- Three repetitions of dense-angle `RY`/`RZ`, a nearest-neighbour CNOT ring,
  and the same rotations again.
- Inverse circuit for the second vector.
- Return \(\exp(\lvert\mathrm{amplitude}[0]\rvert^2)\).

`sin` and `cos` are polynomials inside the TA. A vector compared with itself
returned **2,718,281** in units of \(10^{-6}\). That is \(e \times 10^{6}\)
truncated to an integer (2,718,281.828…), so the inverse brings the state
back to \(\lvert 0\rangle\).

The 20,000-evaluation batch, which is the rate used below, also returned a
mean \(\exp(K)\) of 1.004 on random angles. Unrelated vectors have fidelity
near 0, and \(\exp(0) = 1\).

The pre-existing `--qai` command is a different program: four integer
multiply-adds, with a log line on every call. On this same boot it averaged
**10,757 µs per invoke** over 500 calls before the kernel was added, and
**10,757 µs** again over 50 calls after. That figure is the logged integer
command, not the HAI kernel, and it is not used in the totals below.

---

## 3. Raw secure-world timings

Host clock: `CLOCK_MONOTONIC` around the single invoke. TA clock:
`TEE_GetSystemTime` (millisecond). Date: 15 October 2026. The TA file on the
board was 85,152 bytes. `/dev/tee0` is mode `crw------- root`, so the client
ran as root. `tee-supplicant` was already running.

| Run | Evals inside the TA | TEE time | ms / kernel | Kernels / s | REE wall of that one invoke |
|---|---:|---:|---:|---:|---:|
| Smoke | 20 | 8 ms | 0.400 (coarse; only 8 ticks) | — | 8,383 µs |
| Batch A | 8,000 | 2,116 ms | 0.2645 | 3,780.7 | 2,116,191 µs |
| Batch B | 8,000 | 2,096 ms | 0.2620 | 3,816.8 | 2,095,634 µs |
| Batch C, rate used below | 20,000 | **5,246 ms** | **0.2623** | **3,812.4** | 5,245,950 µs |

Batch C wall time and TEE time differ by less than one millisecond. For a
multi-second command the world switch is inside the TEE clock tick.

Ten further invokes of **one** evaluation each (each invoke also does the
self-check, so two circuits) had REE wall times 788, 784, 791, 598, 594,
595, 598, 593, 593, 594 µs. After the first three, the wall time is about
**0.59 ms** for two circuits plus one entry into the TA. The TEE clock
reported 0 ms or 1 ms on those calls, which is the resolution limit, not a
measured 0 ms kernel.

### Power while batch C ran

PMIC rail sum, same method as the Normal World note. One sample after the
command had already finished is omitted (utilisation 3.3%, 2.12 W).

| Sample while the TA was in the loop | CPU util | Rail power |
|---|---:|---:|
| 0 | 25.0% | 3.071 W |
| 1 | 25.2% | 3.261 W |
| 2 | 25.4% | 3.109 W |
| 3 | 24.9% | 3.097 W |
| 4 | 24.9% | 3.112 W |
| 5 | 25.2% | 3.053 W |
| 6 | 25.1% | 3.093 W |
| Mean of these seven | **25.1%** | **3.114 W** |

Temperature moved from 52.1°C to 53.8°C. Frequency stayed at 2.4 GHz on the
earlier inventory of this board. 25% of four cores is one busy core.

### Memory image of the TA

`aarch64-linux-gnu-size` on the unsigned ELF:

| Section | Bytes |
|---|---:|
| `.text` | 56,224 |
| `.rodata` | 4,682 |
| `.data` | 440 |
| `.bss` | 53,424 |
| Configured stack (`TA_STACK_SIZE`) | 4,096 |
| Configured heap (`TA_DATA_SIZE`) | 32,768 |

`.bss` includes the 6,144 bytes of statevector scratch (256 complex
amplitudes plus a 128-element pair buffer) and the TA heap reservation.
Loaded secure image, sections plus stack, is about
\(56224+4682+440+53424+4096 = 118{,}866\) bytes (**116 KiB**). Linux
`VmRSS` cannot see that secure allocation. The signed `.ta` file is
85,152 bytes.

A streamed kernel row for all 637,200 training vectors is \(637200 \times 8
= 4.86\) MiB in the Normal World. The TA does not allocate it.

---

## 4. Scaling

Rate \(R = 20000 / 5.246 = 3812.4\) kernels per second on one core.
\(N_{\mathrm{train}} = 177 \times 3600 = 637200\).
\(N_{\mathrm{test}} = 123 \times 3600 = 442800\).

| Workload | Calculation | Result |
|---|---|---|
| One sample, full training file | \(637200 / 3812.4\) | **167.1 s** |
| Energy at 3.114 W | \(167.1 \times 3.114\) | **520 J = 0.144 Wh** |
| Rows that fit in 1 s | \(R\) | **3,812** |
| Full test file, one secure core | \(442800 \times 637200 / 3812.4\) | **7.40×10⁷ s = 2.35 years** |
| Dense test kernel matrix | unchanged from the Normal World note | **2,102 GiB**, stored outside the TA if stored at all |

Preprocessing (moving average, z-score, scale to \([-\pi,\pi]\)) was not
ported into the TA. The Normal World timing of that arithmetic remains about
2.8 s for the training file and 1.9 s for the test file, on synthetic data
of the paper’s width.
