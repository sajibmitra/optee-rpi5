# RAM and CPU estimate: HAI CPS classification with the quantum-hybrid SVM

Measured on the connected Raspberry Pi 5 at `skmitra@172.20.10.2` for the
algorithm in Cultice, Onim, Giani, and Thapliyal, *Anomaly Detection for
Real-World Cyber-Physical Security using Quantum Hybrid Support Vector
Machines*, arXiv:2409.04935v1 (ISVLSI 2024).

Local copy of the paper: [`2409.04935v1.pdf`](2409.04935v1.pdf).

The paper reports accuracy (87%, F1 0.86 on 16 features / 8 qubits). It does
not report RAM, CPU time, power, or the number of HAI rows actually passed
into the quantum kernel. The numbers below are from running that circuit on
this Pi and scaling by the dataset lengths the paper states.

---

## 1. Result

Classifying **one** HAI sample against the **full 177-hour training file**
(637,200 rows), using the paper’s best model (16 features, 8 qubits):

| Resource | Measured estimate on this Pi 5 |
|---|---|
| CPU time | **42 minutes** on 1 core, **10.5 minutes** on all 4 cores |
| RAM | **about 37 MiB** if the kernel row is streamed (32 MiB runtime + 4.9 MiB of similarities) |
| Board rail power during the run | **3.2 W** on 1 core, **5.9 W** on 4 cores |
| Energy for that one classification | **2.2 Wh** (1 core) or **1.0 Wh** (4 cores) at those rail powers |

The HAI files are recorded at **1 sample/second**. This Pi can finish a
classification inside that one-second slot only when the new sample is
compared with at most **253 training rows on one core**, or **1,016 rows on
four cores**. Against the full training file it is about **600×** too slow
(about 2,500 cores of this Cortex-A76 would be required for a 1 Hz answer).

Scoring the entire 123-hour test file (442,800 rows) against the full
training file is **35 years** on one core and **8.8 years** on four cores.
The dense kernel matrix would be **2,102 GiB**, which does not fit in the
2 GB of RAM. Streaming one test row at a time stays near 37 MiB.

Classical preprocessing from the paper (60-second moving average,
standardization, 16-feature selection, scale to \([-\pi, \pi]\)) is about
**4.4 µs/row**: **2.8 s** for the training file and **1.9 s** for the test
file. The quantum kernel dominates.

---

## 2. Device

Checked over SSH on 15 October 2026.

| Item | Value |
|---|---|
| Address | `skmitra@172.20.10.2` (ping 4–7 ms, TCP/22 open, key login, no password prompt) |
| Hostname / model | `raspberrypi`, Raspberry Pi 5 Model B Rev 1.1 |
| Kernel | Linux 6.18.46-v8-16k+ #1 SMP PREEMPT Fri Aug 28 05:24:44 +06 2026, aarch64 |
| CPU | 4× ARM Cortex-A76, one thread per core, max 2400 MHz, min 1500 MHz |
| Caches | L1d 256 KiB, L1i 256 KiB, L2 2 MiB (4 instances), L3 2 MiB |
| RAM | `total_mem=2048`, `MemTotal` 2,021,376 kB (1.97 GiB). At idle: 397 MiB used, 1.5 GiB available. Swap 1.9 GiB, unused |
| Storage | 15 GB root, 6.9 GB used, 6.6 GB free |
| Throttle / temperature at idle | `throttled=0x0`, 48.8°C |
| 5 V input | `EXT5V_V` = 5.111 V (input current is not on this PMIC readout) |
| Software present | Python 3.13.5, NumPy 2.2.4 |
| Software absent | Qiskit, scikit-learn, any HAI CSV, any QHSVM script. `sudo` requires a password, so no packages were installed |

Home on the Pi holds OP-TEE trees (`optee-rpi5`, `optee-onpi-build`) only.
The benchmark script was written to `/tmp/qhsvm_pi_bench.py` on the Pi and
was not added to this repository.

---

## 3. What the paper specifies

### 3.1 Dataset (Section III)

HAI 20.07, the HIL-based Augmented ICS security dataset (boiler, turbine,
water treatment, and a hardware-in-the-loop power-grid model):

- 59 features, including set-points, sampled once per second.
- Training data: normal operation for **177 hours**.
- Test data: normal and attack traffic for **123 hours**, **38 attacks**,
  14 attack primitives. The test slice they discuss is about **4%** anomalies.
- Row counts used for scaling, at 1 Hz with no gaps:  
  \(177 \times 3600 = 637{,}200\) training rows,  
  \(123 \times 3600 = 442{,}800\) test rows.  
  Real files can differ slightly if the capture has gaps. The paper gives
  hours, not an exact row count.

### 3.2 Model (Sections II, IV, and Table I)

Hybrid pipeline:

1. Classical preprocessing.
2. Quantum fidelity kernel between the current vector and the training set.
3. One-class SVM (scikit-learn) on that kernel.

Preprocessing (Section IV-A):

- Moving average of 60 overlapping samples, equation (2).
- Categorical fields replaced by histogram values.
- Z-score standardization, equation (3).
- Feature ranking by decision-tree Gini impurity. The kept width equals the
  number of encoded features (16 in the best model).
- Values mapped into \([-\pi, \pi]\) for angle embedding.

Kernel (Sections II-B and IV-B):

- Dense angle encoding: two features per qubit, so 16 features use 8 qubits
  (LaRose and Coyle, cited as [3]).
- Feature map inspired by Woźniak et al.: two rotational degrees of freedom,
  nearest-neighbour entanglement, and a repeated rotation. The map \(U(x)\)
  is applied **three times**.
- Fidelity by the Hilbert–Schmidt inner product (Havlíček et al.): apply
  \(U(x_i)\), then \(U^\dagger(x_j)\), and take the probability of returning
  to \(\lvert 0\rangle^{\otimes n}\):

  \[
  K(x, y) = \lvert\langle 0\rvert U(y)^\dagger U(x)\lvert 0\rangle\rvert^2
  \]

- Post-process \(k_p(x_i, x_j) = e^{k(x_i, x_j)}\).
- Training kernel is the symmetric Gram matrix of the training set. The test
  kernel is every test row against every training row, which the paper writes
  as \(O(\lvert x_{\mathrm{input}}\rvert \times \lvert x_{\mathrm{train}}\rvert \times \mathrm{shots})\).
- Reported runs used **IBM Qiskit with no noise model**. For a noiseless
  statevector that is **one circuit per pair** (the amplitude is exact). A
  shot loop appears only if the same circuit is executed on a QPU.

Decision function: one-class SVM, equation (4). In a trained SVM only support
vectors have a non-zero multiplier. The paper’s test procedure still builds
the inner product against the **training set**, so the cost model here uses
every training row. The paper never publishes the support-vector count.

Table I, best row: **16 features, 8 qubits, accuracy 87%, precision 0.88,
recall 0.87, F1 0.86**. The same width with a classical kernel is 73%
accuracy and F1 0.65 (a 14-point accuracy gap). Configurations with 8 and 24
features were worse for the quantum kernel (86% and 82%).

Figure 5 is an **example** test kernel: 1,000 normal rows followed by 500
anomalous rows. The caption does not state how many training columns that
image has.

Section VI states that this kernel is too expensive for second-scale or
minute-scale detection on current quantum hardware, because of the same
\(O(\lvert x_{\mathrm{input}}\rvert \times \lvert x_{\mathrm{train}}\rvert \times \mathrm{shots})\)
circuit count. The Pi measurement is the classical-simulation version of that
statement.

---

## 4. Procedure

### 4.1 Connect and inventory

```bash
ping -c 3 -W 2 172.20.10.2
nc -z -w 3 172.20.10.2 22
ssh -o BatchMode=yes -o ConnectTimeout=10 skmitra@172.20.10.2
```

On the Pi:

- `cat /proc/device-tree/model`, `uname -a`, `nproc`, `lscpu`, `free -h`
- `vcgencmd measure_temp`, `vcgencmd get_throttled`, `vcgencmd get_config total_mem`
- `vcgencmd pmic_read_adc` for rail voltage and current
- `python3 -c "import numpy"` → NumPy 2.2.4
- `import sklearn` and `import qiskit` both failed
- `find` under the home directory for `hai`, `qhsvm`, `qsvm`, `quantum` found
  no dataset and no classifier

### 4.2 Circuit that was timed

Qiskit is not installed, and the 2 GB board was not given a Qiskit install.
The timed kernel is a NumPy statevector (complex128, dimension \(2^8 = 256\))
of the circuit described in Sections II and IV:

- Start in \(\lvert 0\rangle^{\otimes 8}\).
- Repeat 3 times for the data vector \(x \in [-\pi,\pi]^{16}\):
  - On qubit \(q\), `RY(x[2q])` then `RZ(x[2q+1])`.
  - Ring of CNOTs, control \(q\) to target \((q+1) \bmod 8\), for \(q = 0..7\).
  - The same `RY` / `RZ` pair again (the paper’s “repeated rotation”).
- Apply the inverse for the second vector \(y\): same gates in reverse order,
  with angles negated. CNOT is its own inverse, so the ring is walked
  backwards.
- \(K = \lvert\mathrm{amplitude}[0]\rvert^2\), then return \(e^{K}\).

Figure 4 is a drawing. The PDF text does not list the exact Qiskit gate
schedule, so `RY`/`RZ` dense-angle encoding plus a nearest-neighbour ring is
the circuit implied by Sections II-A and IV-B. A point compared with itself
returned **2.718282**, which is \(e^1\). That checks the inverse: identical
inputs must have fidelity 1, and the paper’s exponential post-process then
returns \(e\).

Gate applications are plain NumPy slices on a 256-element vector. Single-qubit
gates rebuild a 2×2 matrix per call, and each CNOT rebuilds an index vector.
That Python overhead is part of the measured 3.95 ms. An Aer-style C simulator
of the same 8-qubit circuit can be faster. A Qiskit program that rebuilds a
`QuantumCircuit` per pair is often slower, and the Qiskit process itself
usually holds hundreds of megabytes. Those two effects were not measured here.

### 4.3 Timing and power

1. Warm up a few kernel calls.
2. Sample idle rail power five times, 0.3 s apart.
3. Time 1,000 kernel evaluations of one query against 1,000 random training
   vectors in \([-\pi,\pi]^{16}\).
4. Run one core for 25 s (6,334 evaluations). In parallel, once per ~1.5 s,
   read:
   - CPU utilisation from `/proc/stat` (total jiffies minus idle+iowait)
   - `scaling_cur_freq` for `cpu0`
   - `vcgencmd measure_temp`
   - `vcgencmd pmic_read_adc`
5. Repeat with a `multiprocessing` pool of 4 workers for 12 s (12,200
   evaluations) and the same power samples.
6. Time preprocessing on a synthetic 20,000×59 array and scale to the paper’s
   row counts. The array is not the HAI CSV. The arithmetic (cumsum moving
   average, mean/std, min-max into \([-\pi,\pi]\)) matches the paper’s
   formulas, not its particular Gini-selected columns.

Rail power is the sum of \(V \times I\) over every PMIC channel that publishes
both a voltage and a current (`3V7_WL_SW`, `3V3_SYS`, `1V8_SYS`, `1V1_SYS`,
`0V8_SW`, `VDD_CORE`, HDMI, and the smaller always-on rails). DDR current
read 0 A in these samples. This is power delivered on the board rails. It is
smaller than wall-socket power, because the 5 V input current is not metered
and converter loss is outside the sum.

`ru_maxrss` and `/proc/self/status` (`VmRSS`, `VmHWM`, `VmPeak`, `VmSize`)
were read at the end of the 1,000-evaluation run.

---

## 5. Raw measurements

### 5.1 Idle

| Sample | Rail power (W) |
|---|---|
| 1–5 | 2.094, 2.094, 2.134, 2.119, 2.100 |
| Mean | **2.108 W** |

Process RSS after NumPy import and the statevector scratch arrays: **31,920 KiB**
(`ru_maxrss`). `/proc/self/status` at the end of the first timing run:

| Field | Value |
|---|---|
| `VmRSS` | 32,368 kB |
| `VmHWM` | 32,368 kB |
| `VmPeak` | 190,768 kB |
| `VmSize` | 125,232 kB |

`VmHWM` is the RAM high-water mark (32 MiB). `VmPeak` is virtual address
space, mostly the interpreter and NumPy mappings, not extra anonymous RAM.

### 5.2 One core

| Run | Evaluations | Wall time (s) | ms / kernel | Kernels / s |
|---|---|---|---|---|
| Short | 1,000 | 4.081 | 4.081 | 245.1 |
| Sustained | 6,334 | 25.003 | **3.947** | **253.3** |

Sustained-run side channels (12 samples, ~1.5 s apart):

| Quantity | Value |
|---|---|
| CPU utilisation | 25.0–25.9%, mean **25.2%** (one of the four cores) |
| `cpu0` frequency | 2,400,000 kHz for every sample |
| Rail power | mean **3.186 W**, max **3.614 W** |
| Temperature | 51.0°C → 55.4°C |

The rate used below is the sustained run: **253.3 kernels/s/core**,
**3.947 ms** of core time per kernel.

### 5.3 Four cores

Pool of 4 processes, each burning for 12 s:

| Worker | Evaluations | ms / kernel |
|---|---|---|
| 0 | 3,052 | 3.933 |
| 1 | 3,038 | 3.951 |
| 2 | 3,057 | 3.926 |
| 3 | 3,053 | 3.932 |
| Total | **12,200** in 12.06 s wall | **1,016 kernels/s** aggregate |

Per-kernel core time did not change (3.93 ms). Speedup versus one core is
\(1016 / 253.3 = 4.01\), so the workload scales across the four cores.

| Quantity | Value |
|---|---|
| CPU utilisation | 100% after the first sample (first sample 74.8% while the pool started) |
| Rail power | mean **5.862 W**, max **5.908 W** |
| Temperature | 56.0°C → 63.7°C |

### 5.4 Preprocessing micro-benchmark

20,000 synthetic rows × 59 features, window 60, z-score, then 16 columns
scaled to \([-\pi, \pi]\):

| Quantity | Value |
|---|---|
| Wall time | 0.0875 s |
| Per input row | 4.37 µs |
| Scaled to 637,200 training rows | 2.79 s |
| Scaled to 442,800 test rows | 1.94 s |

---

## 6. Scaling arithmetic

Let \(t = 1/253.3 = 3.947\times 10^{-3}\) seconds be the measured core time
of one fidelity evaluation, and \(R_4 = 1016\) kernels/s the measured
four-core rate.

One classified row against \(N\) training rows:

\[
T_1(N) = N \times t, \qquad T_4(N) = N / R_4
\]

RAM to hold one kernel row, plus the measured runtime:

\[
\mathrm{RAM}(N) \approx 32\,\mathrm{MiB} + N \times 8\,\mathrm{bytes}
\]

A stored test kernel of \(N_{\mathrm{test}}\) rows is
\(N_{\mathrm{test}} \times N \times 8\) bytes. The SVM decision after the
kernel is one dot product of that row with the dual coefficients and is
omitted; it is far smaller than \(T_1(N)\).

### 6.1 One HAI sample against the full training file

\(N = 637{,}200\).

| Quantity | Calculation | Result |
|---|---|---|
| 1 core | \(637200 / 253.3\) | **2,515 s = 41.9 min** |
| 4 cores | \(637200 / 1016\) | **627 s = 10.4 min** |
| Kernel-row RAM | \(637200 \times 8\) | **4.86 MiB** |
| Process + row | 32 MiB + 4.86 MiB | **about 37 MiB** |
| Core-seconds per plant second | \(637200 \times 0.003947\) | **2,515** |
| 1 Hz fit on this Pi | \(253\) rows (1 core) or \(1016\) rows (4 cores) | full file is **~600×** too large |

Energy at the measured mean rail power, for that single classification:

| Mode | Time × power | Energy |
|---|---|---|
| 1 core | \(2515\,\mathrm{s} \times 3.186\,\mathrm{W}\) | **8.0 kJ = 2.2 Wh** |
| 4 cores | \(627\,\mathrm{s} \times 5.862\,\mathrm{W}\) | **3.7 kJ = 1.0 Wh** |

Incremental energy above the 2.108 W idle baseline is about **0.75 Wh**
(1 core) and **0.65 Wh** (4 cores). Four cores finish sooner, so the extra
joules are similar even though the instantaneous power is higher.

### 6.2 Full test file against the full training file

\(442{,}800 \times 637{,}200 = 2.8215\times 10^{11}\) kernel evaluations.

| Quantity | Result |
|---|---|
| 1 core | \(2.8215\times 10^{11} / 253.3 = 1.114\times 10^{9}\,\mathrm{s}\) = **35.3 years** |
| 4 cores | \(2.8215\times 10^{11} / 1016 = 2.777\times 10^{8}\,\mathrm{s}\) = **8.8 years** |
| Dense matrix | \(442800 \times 637200 \times 8\) = **2,102 GiB** |
| Streamed RAM | still **about 37 MiB** (one test row at a time) |
| Preprocessing both files | **about 4.7 s** |

### 6.3 Figure 5’s 1,500 test rows

The figure is 1,000 normal rows plus 500 anomalous rows. The training width
is not in the paper. Against the full 637,200-column training file:

| Quantity | Result |
|---|---|
| 1 core | \(1500 \times 2515\,\mathrm{s}\) = **1,048 hours** |
| 4 cores | **262 hours** |
| Dense kernel | \(1500 \times 4.86\,\mathrm{MiB}\) = **7.12 GiB** (larger than this board) |
| Streamed RAM | **about 37 MiB** |

For any smaller training subset of width \(N\) that the authors may have used
to draw the figure:

\[
T_1 = 1500 \times N \times 3.947\,\mathrm{ms}, \qquad
\mathrm{matrix} = 1500 \times N \times 8\,\mathrm{bytes}
\]

---

## 7. How to read the estimate

- The Pi can **store and run** the 8-qubit classifier. Working RAM stays near
  **37 MiB** for one streamed prediction against the full training file, well
  inside 2 GB.
- It cannot **keep up with HAI’s 1 Hz plant rate** if every historical
  training second is a kernel column. The measured ceiling is about **10³**
  training rows per second on four cores, against **6.37×10⁵** training rows
  in the paper’s 177-hour file.
- Electrical cost of one full-file classification on this board is about
  **1–2 Wh** of PMIC rail energy, depending on whether one core runs for
  42 minutes or four cores run for 10 minutes.
- Preprocessing is a few seconds for the whole corpus. Section IV’s circuit
  count is the cost that matters.
- These times are for **noiseless simulation**, which is how the paper
  produced Table I. A real 8-qubit QPU would replace each 3.95 ms simulation
  with one circuit execution times the shot count, plus queueing. The paper’s
  complexity formula includes that shot factor; this measurement does not,
  because the amplitude was computed exactly.

Limits of the measurement:

- Gate schedule follows the paper’s text (dense-angle `RY`/`RZ`, ring CNOT,
  repeated rotation, three repetitions). It is not a bit-exact replay of an
  unpublished Qiskit listing or of the pixels in Figure 4.
- NumPy on CPython is the runtime. Qiskit Aer or a C statevector may spend
  less CPU per kernel. A Qiskit Python driver may spend more, and it would
  raise the RAM floor.
- HAI row counts are \(3600 \times\) the hours printed in Section III.
- Gini feature selection was not re-run; preprocessing time uses 16 of 59
  columns after a vectorised moving average.
- Rail power excludes wall-adapter loss and any 5 V current that never
  appears as a PMIC channel.
