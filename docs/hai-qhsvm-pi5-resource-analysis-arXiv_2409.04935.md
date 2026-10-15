# Hardware analysis: HAI quantum-hybrid SVM on a Raspberry Pi 5

Companion to the numeric estimate in
[`hai-qhsvm-pi5-resource-estimate-arXiv_2409.04935.md`](hai-qhsvm-pi5-resource-estimate-arXiv_2409.04935.md).
Paper: Cultice, Onim, Giani, and Thapliyal, arXiv:2409.04935v1, local copy
[`2409.04935v1.pdf`](2409.04935v1.pdf).

This note answers three questions:

1. What procedure produced the RAM, CPU-time, and power figures.
2. Whether that classifier, or the QAI Trusted Application in this repository,
   needs a GPU, another accelerator, or a quantum processor.
3. What training needs, what inference needs, and whether inference runs on
   the Pi’s CPU alone.

## Fact that bounds every number

The Raspberry Pi 5 at `skmitra@172.20.10.2` has no quantum processor, no GPU,
and no neural accelerator. The paper’s published HAI results were also not
produced on a quantum processor. Section V of arXiv:2409.04935 says the
quantum operations were **simulated with IBM Qiskit and no noise model**.

The measurement on this board is the same kind of work, done with a smaller
runtime: a **classical statevector simulation** of the 8-qubit fidelity
circuit, executed as ordinary ARM floating-point code on the Cortex-A76.
No qubit was executed on hardware. The CPU times below are the cost of that
simulation. They are not the cost of a quantum processor, because none is
present and none was used.

Two different programs are easy to mix up. They are kept separate below.

| Program | What it actually executes |
|---|---|
| arXiv:2409.04935 quantum-hybrid SVM | For every pair of 16-feature vectors, simulate an 8-qubit circuit, read the fidelity, then apply a classical one-class SVM. This is what was timed on the Pi. |
| QAI Trusted Application in `optee_examples/qai_ta` | Four integer features. Inference is a handful of 64-bit multiply-adds inside OP-TEE (`qai_infer_qai` in `ta/inference.c`). The name is quantum-inspired. The binary does not simulate a circuit and does not call a quantum device. |

---

## 1. Measurement procedure

Date: 15 October 2026. Host: this workspace. Target: `skmitra@172.20.10.2`.
Nothing was installed. `sudo` on the Pi asks for a password, Qiskit and
scikit-learn are not installed, and no HAI CSV is on the board. NumPy 2.2.4
and Python 3.13.5 were already there. The benchmark file
`/tmp/qhsvm_pi_bench.py` lived only on the Pi’s `/tmp` and is not in this
repository.

### 1.1 Confirm the board and the software

From the development machine:

```bash
ping -c 3 -W 2 172.20.10.2
nc -z -w 3 172.20.10.2 22
ssh -o BatchMode=yes -o ConnectTimeout=10 skmitra@172.20.10.2
```

Ping returned in 4–7 ms with no loss. TCP port 22 accepted the connection.
SSH used an existing key (`BatchMode`, so it would have failed rather than
ask for a password).

On the Pi the following were read once, before any benchmark:

| Command | What it established |
|---|---|
| `cat /proc/device-tree/model` | Raspberry Pi 5 Model B Rev 1.1 |
| `uname -a` | Linux 6.18.46-v8-16k+, aarch64 |
| `nproc`, `lscpu` | 4× Cortex-A76, max 2400 MHz |
| `free -h`, `awk` on `MemTotal` | 2,021,376 kB RAM, about 1.5 GiB available, swap unused |
| `vcgencmd get_config total_mem` | `total_mem=2048` |
| `vcgencmd get_throttled` | `0x0` (not thermally or undervoltage throttled) |
| `vcgencmd measure_temp` | 48.8°C at idle |
| `vcgencmd pmic_read_adc` | Per-rail voltage and current. `EXT5V_V` = 5.111 V. There is no input-current channel, so wall-socket watts are not observed |
| `python3 -c "import numpy"` | NumPy 2.2.4 |
| `import sklearn`, `import qiskit` | Both missing |
| `find` for `hai`, `qhsvm`, `qsvm`, `quantum` under the home directory | No dataset and no classifier. Home contains OP-TEE trees only |

CPU frequency during the later runs was read from
`/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq` and stayed at
2,400,000 kHz.

### 1.2 Circuit that was timed

The paper’s best HAI model (Table I) is 16 features on 8 qubits. Section IV-B
specifies a feature map with two rotational degrees of freedom, nearest-neighbour
entanglement, a repeated rotation, and **three** repetitions of that map.
Fidelity is the Hilbert–Schmidt test in Section II-B: apply \(U(x)\), then
\(U(y)^\dagger\), and take the probability of measuring the all-zero state.
The kernel value used by the SVM is \(e\) raised to that probability.

Figure 4 does not list a Qiskit gate schedule in the text, and Qiskit was not
available to replay one. The timed circuit is the schedule implied by that
text:

1. Allocate a length-256 complex vector (an 8-qubit statevector, 4 KiB) and
   set amplitude 0 to 1.
2. Repeat three times for the first vector \(x\), whose 16 entries are already
   in \([-\pi, \pi]\):
   - On qubit \(q\), apply `RY(x[2q])` and `RZ(x[2q+1])`.
   - Apply eight CNOTs in a ring, control \(q\) to target \((q+1) \bmod 8\).
   - Apply the same `RY` / `RZ` pair again.
3. Repeat three times in reverse for the second vector \(y\), with the angles
   negated. Each CNOT is its own inverse, so the ring is walked from qubit 7
   down to qubit 0.
4. Return \(\exp(\lvert\mathrm{amplitude}[0]\rvert^2)\).

Each single-qubit gate is a 2×2 multiply on the 128 pairs of amplitudes
selected by that qubit’s bit. Each CNOT swaps amplitudes in software. All of
this is NumPy on the CPU. There is no call into a GPU library and no call to
a quantum backend.

A vector compared with itself returned **2.718282**, which is \(e^1\).
Identical inputs must have fidelity 1, and the paper’s exponential
post-process then returns \(e\). That check passed before any timing number
was kept. Random vectors in \([-\pi, \pi]^{16}\) were used afterwards. Once
the features are in that range, every sample runs the same gate count, so the
kernel time does not depend on the original HAI sensor values. The HAI file
itself was not on the Pi and was not downloaded.

### 1.3 CPU time

The script stayed in one process for the single-core runs.

1. Three warmup calls, discarded, so the first timed call was not paying for
   page-in of the NumPy code paths.
2. One query vector against 1,000 training vectors, timed with
   `time.perf_counter` around the whole loop. Result: **1,000 evaluations in
   4.081 s** (4.081 ms each, 245 per second).
3. A second run held one core for 25 s so the rate was not a short-loop
   accident: **6,334 evaluations in 25.003 s**, which is **3.947 ms** each
   and **253.3 kernels per second**. This sustained rate is the one used for
   every scaled estimate.

CPU utilisation was computed from `/proc/stat` between samples about 1.5 s
apart: total jiffies minus idle and iowait, divided by the change in total
jiffies. During the 25 s run the four-core utilisation sat at **25.0–25.9%**
(mean 25.2%). That is one busy core and three idle cores, which matches a
single-threaded Python loop.

The four-core run used `multiprocessing.Pool(4)`. Each worker ran the same
fidelity function for 12 s on its own copy of the statevector. Together they
finished **12,200 evaluations in 12.06 s of wall time**, **1,016 kernels per
second**. Each worker still took 3.93 ms of its own core per kernel.
\(1016 / 253.3 = 4.01\), so the extra cores did not interfere and did not
get a super-linear shortcut. After the pool had started, `/proc/stat`
reported **100%** utilisation.

### 1.4 RAM

At the end of the 1,000-evaluation process:

| Source | Value | Meaning |
|---|---|---|
| `resource.getrusage(...).ru_maxrss` | 31,920 KiB | Peak resident set of that process |
| `VmRSS` | 32,368 kB | Resident set at the instant it was read |
| `VmHWM` | 32,368 kB | High-water resident set, **32 MiB** |
| `VmPeak` | 190,768 kB | Peak virtual size, including mappings that were not all resident |
| `VmSize` | 125,232 kB | Virtual size at the end |

The 8-qubit state itself is 256 complex128 values, 4 KiB. The 32 MiB is the
CPython and NumPy process, not a large model. A kernel row against the full
training length is stored separately in the scaling step: \(637200 \times 8\)
bytes = **4.86 MiB**. Adding that row to the measured process gives the
**37 MiB** figure for one streamed classification. That addition is
arithmetic. A 637,200-wide row was not allocated on the Pi during the timing
run.

### 1.5 Electrical power

`vcgencmd pmic_read_adc` prints a current and a voltage for each named rail.
Power for one sample is the sum of \(V \times I\) over rails that publish
both. Rails seen in the readout include `3V7_WL_SW`, `3V3_SYS`, `1V8_SYS`,
`1V1_SYS`, `0V8_SW`, `VDD_CORE`, HDMI, and the small always-on rails. DDR
current read 0 A. `EXT5V_V` is the input voltage only.

This sum is power **on the board rails**. It is not wall-socket power. Adapter
loss and any 5 V current that never appears as a rail current are outside the
measurement.

| Condition | How it was taken | Result |
|---|---|---|
| Idle | 5 samples, 0.3 s apart, before the timed loop | 2.094, 2.094, 2.134, 2.119, 2.100 W, mean **2.108 W** |
| One core, 25 s | 12 samples about 1.5 s apart, concurrent with the burn | mean **3.186 W**, max 3.614 W, die 51–55°C |
| Four cores, 12 s | 8 samples about 1.2 s apart, concurrent with the pool | mean **5.862 W**, max 5.908 W, die 56–64°C |

### 1.6 Preprocessing time

Section IV-A of the paper, before any circuit, is a 60-sample moving average,
a z-score, Gini feature selection down to 16 columns, and a map into
\([-\pi, \pi]\). Gini selection was not re-fit. The timed piece is the
vectorised arithmetic on a synthetic \(20000 \times 59\) array: cumulative-sum
moving average with window 60, mean and standard deviation, then min-max of
16 columns into \([-\pi, \pi]\).

That took **0.0875 s**, **4.37 µs per row**. Scaling by the paper’s durations
at 1 Hz gives **2.79 s** for \(177 \times 3600 = 637200\) training rows and
**1.94 s** for \(123 \times 3600 = 442800\) test rows. This is a cost estimate
for that arithmetic, not a replay of the HAI file.

### 1.7 How the HAI totals were obtained

The paper gives hours, not a published kernel width. The scaling uses one
sample per second and no gaps:

\[
N_{\mathrm{train}} = 177 \times 3600 = 637200, \qquad
N_{\mathrm{test}} = 123 \times 3600 = 442800
\]

One classification against every training row, using the sustained rates:

\[
T_1 = 637200 / 253.3 = 2515\,\mathrm{s} = 41.9\,\mathrm{min}
\]

\[
T_4 = 637200 / 1016 = 627\,\mathrm{s} = 10.4\,\mathrm{min}
\]

Energy at the measured mean rail power:

\[
2515 \times 3.186\,\mathrm{W} = 8.0\,\mathrm{kJ} = 2.2\,\mathrm{Wh}
\]

\[
627 \times 5.862\,\mathrm{W} = 3.7\,\mathrm{kJ} = 1.0\,\mathrm{Wh}
\]

The full test file is \(442800 \times 637200 = 2.8215 \times 10^{11}\)
circuits: **35.3 years** on one core and **8.8 years** on four cores. The
dense matrix is **2,102 GiB**. Streaming one test row at a time does not
allocate that matrix, so RAM stays near 37 MiB.

A 1-second plant period can absorb 253 kernel evaluations on one core, or
1,016 on four cores. The full training file is about 600 times longer than
that budget. Equivalently, \(637200 \times 3.947\,\mathrm{ms} = 2515\)
core-seconds of work arrive every plant second.

Figure 5’s 1,500 illustrated test rows are scaled the same way only when the
training width is taken to be the full 637,200. The paper does not print that
width. Those 1,500 rows would then take 1,048 hours on one core, and the
dense block would be 7.12 GiB.

---

## 2. Does this need a GPU, an accelerator, or a quantum processor?

**No.** Not for the paper’s published experiment, not for the measurement on
this Pi, and not for the QAI Trusted Application that this repository
actually builds.

### The paper’s classifier

Section V states that the HAI numbers came from a **noiseless Qiskit
simulation**. A simulator is a classical program. The algorithm’s kernel is
defined with quantum gates, but evaluating it for Table I did not require a
quantum processor. The paper also does not use a GPU or an NPU as part of the
method. scikit-learn’s one-class SVM, which they name as the classifier, is a
CPU quadratic program on a precomputed kernel matrix.

A quantum processor could, in principle, replace each simulated fidelity with
a shot-based circuit execution. This Pi does not have one, and current
embedded boards do not have one. A GPU can speed up some statevector
simulators. It is an optional implementation choice. The circuit has 8 qubits
and 256 amplitudes, so the working state is 4 KiB and does not need a GPU to
fit or to run.

What the Pi measurement used:

| Hardware | Used? |
|---|---|
| Cortex-A76 CPU | Yes. All kernel evaluations and the preprocessing micro-benchmark |
| GPU | No GPU is on this board, and no GPU library was called |
| NPU or other accelerator | No |
| Quantum processor | No. None is attached, and the statevector never left the CPU |

### The QAI Trusted Application in this repository

`qai_infer_qai` in `optee_examples/qai_ta/ta/inference.c` computes

\[
\mathrm{score} = \mathrm{bias} + \sum_i \theta_i x_i + \sum_i \gamma_i x_i x_{i+1}
\]

on four `int32` features, with `int64` accumulators, then divides by a fixed
scale. The resident parameters are eight integers plus a bias
(`ta/model_params.h`). The comment in that header calls the model
quantum-inspired. The instructions are ordinary integer multiply-adds in the
OP-TEE Trusted Application, which runs on the same ARM CPU in Secure World.

The roadmap (`docs/qai-optee-prototype-roadmap.md`, Phase 6) says not to put
Qiskit inside the Pi or the Trusted Application. The checked-in trainer
`tools/train_qai_hybrid.py` is classical gradient descent in the Python
standard library. It does not import Qiskit, PennyLane, NumPy, or a GPU
framework.

So the deployed QAI path has the same hardware answer: CPU only.

---

## 3. Training and inference, separately

### 3.1 arXiv:2409.04935

**Training** is offline relative to the plant, and it is classical except for
the simulated kernel.

1. CPU preprocessing of the 177-hour normal file: moving average, z-score,
   decision-tree Gini ranking, scale the 16 kept features to \([-\pi, \pi]\).
   The arithmetic portion is a few seconds on this Pi (Section 1.6). Fitting
   the decision tree was not re-run here. That fit is also a CPU workload in
   the usual scikit-learn implementation. The paper does not call a GPU for it.
2. The training kernel is one 8-qubit fidelity simulation per unordered pair
   of training rows. On this Pi that is 3.947 ms of one core per pair. A full
   \(637200 \times 637200\) Gram matrix is not a practical training run on
   this board: the matrix is thousands of gigabytes, and the pair count is
   orders of magnitude above the 35-year test-time figure. The paper does not
   say they trained on every second of the 177 hours. Whatever subset they
   used, each pair is still a CPU simulation (Qiskit in their case, NumPy
   statevector in ours), then a CPU one-class SVM on that matrix.
3. No quantum processor is required to reproduce the kind of result they
   published. No GPU is required. A remote quantum processor would change the
   kernel step into shot-based hardware execution, which this embedded board
   cannot host.

**Inference** is one new 16-feature vector:

1. The same classical preprocessing for that vector (and the 60-sample window
   behind it). CPU.
2. One fidelity simulation against each training vector that the SVM still
   needs. The paper’s test description builds the inner product with the
   training set. A standard SVM can instead use only the support vectors.
   The paper does not publish that count, so the estimate uses every training
   row. Each of those simulations is CPU work, 3.947 ms on one core of this
   Pi.
3. A dot product of that kernel row with the stored dual coefficients, plus
   the bias and threshold in equation (4). That step is negligible next to
   the simulations, and it is CPU arithmetic.

**Inference therefore runs on the target device using only its CPU.** The
1,000-evaluation and 6,334-evaluation runs were that inference kernel, on
this Pi, with no accelerator. RAM for a streamed prediction against the full
177-hour file is about 37 MiB. The limit is time, not a missing device: one
such prediction takes 42 minutes on one core and 10.5 minutes on four cores,
which is far outside the 1-second spacing of the HAI samples.

### 3.2 QAI Trusted Application

**Training** does not run on the Pi in the current design. `tools/train_qai_hybrid.py`
runs on the development host. It draws a synthetic 4-feature set, runs
gradient descent in pure Python, and prints integer \(\theta\) and \(\gamma\)
for `model_params.h`. Hardware required: a CPU that can run CPython. No GPU,
no accelerator, and no quantum processor. The roadmap’s remark that a Mac
*could* train with Qiskit is not what the script does.

**Inference** is `qai_infer_qai`, compiled into the Trusted Application and
executed by the secure-world CPU when `qai_host` sends `TA_QAI_CMD_INFER_QAI`.
Four features in, one score and a class bit out. No GPU, no accelerator, no
quantum processor, and no statevector. The Normal World does not need one
either. The host only forwards features and reads the prediction back.

---

## 4. Short answers

1. The figures come from an SSH session on this Pi 5, a NumPy statevector of
   the paper’s 8-qubit, 3-repetition fidelity kernel, timed at 253.3
   kernels/s on one Cortex-A76 and 1,016/s on four, with a 32 MiB resident
   process and PMIC rail power of 2.11 W idle, 3.19 W on one core, and 5.86 W
   on four cores. HAI totals multiply that rate by \(177 \times 3600\) and
   \(123 \times 3600\).
2. Neither the measured classifier nor the QAI Trusted Application requires a
   GPU, another accelerator, or a quantum processor. The paper’s own HAI
   table is a noiseless classical simulation. This board has nowhere to send
   a quantum circuit.
3. For the paper, both training and inference are CPU work. The expensive
   part of each is the fidelity simulation. Inference of that kernel does run
   on this Pi’s CPU alone, at about 37 MiB, and it is too slow to classify
   every HAI second against the full training file. For the QAI Trusted
   Application, training is a small CPU Python job on the development host,
   and inference is integer arithmetic on the Pi’s CPU inside OP-TEE.
