# QMOC-SVM on HAI 20.07, inside the Trusted Application

QMOC-SVM is the 8-qubit fidelity one-class model with the robustness changes
applied: one circuit repetition instead of three, an angle bandwidth chosen
from training pairs, 1,000 normal landmarks instead of 200, and `nu` chosen
on held-out normal rows. The kernel ran in the OP-TEE Trusted Application on
the Raspberry Pi 5 at `skmitra@172.20.10.2`, command
`TA_QAI_CMD_QMOC_BLOCK`. The one-class SVM was fit on the host from those
kernel values, the same split of work as the earlier fidelity scoring.

The test rows are the same 600-row HAI draw (400 normal, 200 attack, seed
2409). Positive class is attack.

---

## 1. What changed from the previous fidelity run

| | Previous fidelity kernel | QMOC-SVM |
|---|---|---|
| Command | `TA_QAI_CMD_QOC_BLOCK` | `TA_QAI_CMD_QMOC_BLOCK` |
| Repetitions of the entangling layer | 3 | 1 |
| Angle scale | full \([-\pi,\pi]\) | \(\times 0.18\), chosen below |
| Normal landmarks | 200 | 1,000 |
| `nu` | swept after the fact; all four gave the same labels | chosen on 400 held-out normal rows |

The 3-repetition command is unchanged. A one-row self-check on that command
still returns \(\exp(K) = 2.718282\).

The 1,000 landmarks are normal rows from the HAI training files. The first
200 are the previous reference set. The angle min/max stay those of that
200-row set, so the test rows are the same vectors as `query.bin`, then
multiplied by 0.18. The 400 calibration rows are the next normal training
rows. They are not in the landmark set and not in the test set.

---

## 2. Bandwidth and `nu`, chosen without the test labels

On 48 training landmarks, the TA evaluated the 1-repetition kernel at nine
scales. The scale whose off-diagonal median fidelity is inside \([0.1, 0.5]\)
and closest to 0.30 is **0.18** (median fidelity 0.280). The same scale on
the full 1,000×1,000 Gram matrix has off-diagonal median fidelity **0.273**.
The diagonal fidelity is 1.000, so \(\exp(K)\) on a row compared with itself
is \(e\).

| Scale | Median fidelity, 48 training rows |
|---:|---:|
| 1.00 | 0.002 |
| 0.50 | 0.004 |
| 0.25 | 0.083 |
| 0.20 | 0.203 |
| **0.18** | **0.280** |
| 0.15 | 0.421 |
| 0.10 | 0.689 |
| 0.05 | 0.914 |
| 0.02 | 0.986 |

`nu` was then chosen so the fraction of the 400 calibration normals flagged
as attack is as close as possible to 5%.

| nu | Calibration false-alarm rate | Support vectors |
|---:|---:|---:|
| **0.01** | **0.065** | **55** |
| 0.02 | 0.065 | 55 |
| 0.05 | 0.082 | 80 |
| 0.10 | 0.130 | 118 |
| 0.20 | 0.205 | 215 |

`nu = 0.01` and `nu = 0.02` flag the same 6.5% of calibration normals and
produce the same test labels. The smaller value is the one reported.

---

## 3. Time in the TA

Rate is about 0.085 ms per pair, against 0.247 ms per pair for the
3-repetition QOC-SVM kernel.

| Kernel | Pairs | TEE time | ms / pair |
|---|---:|---:|---:|
| Gram, 1,000×1,000 | 1,000,000 | 84,783 ms | 0.085 |
| Calibration, 400×1,000 | 400,000 | 33,724 ms | 0.084 |
| Test, 600×1,000 | 600,000 | 50,848 ms | 0.085 |
| Total | 2,000,000 | **169.4 s** | 0.085 |

One test row against the 1,000 landmarks takes **84.7 ms** of TA time. QOC-SVM
took 49.4 ms per test row because it used 200 landmarks, even though each
pair was slower.

---

## 4. Memory

All three models share one signed image, so the secure-world
reservation does not grow when QMOC-SVM is added. The Pi has 2,021,376 kB
of Normal World RAM. None of these models approaches that.

### Shared Trusted Application

Measured on the ELF that ran on the Pi:

| Region | Bytes |
|---|---:|
| Signed `.ta` file | 85,152 |
| `.text` | 57,736 |
| `.rodata` | 4,895 |
| `.data` | 440 |
| `.bss` | 53,424 |
| ELF span through the end of `.bss` | 132,712 |
| Stack, `TA_STACK_SIZE`, added on each call | 4,096 |
| Reserved for one TA call | **136,808** |

The 32,768-byte heap (`TA_DATA_SIZE`, symbol `ta_heap`) sits inside `.bss`,
so it is already in the 132,712-byte span. The fidelity statevector is also
in `.bss` and stays resident even for a TinyML call, because it is the same
TA: `psi_re` and `psi_im` are 2,048 bytes each, `tmp_re` and `tmp_im` are
1,024 bytes each, **6,144 bytes** total.

### Bytes that belong to each model

Weights are the `.rodata` arrays. “One new row” is the Normal World state
required after the fit, when a single HAI row is classified. The kernel
matrices are the files this experiment actually held while producing the
scores above.

| Model | Weights in the TA | TA scratch for one call | One new row after the fit | Matrices held for this score |
|---|---:|---:|---:|---:|
| TinyML | 68 | 2,048-byte feature chunk | 64-byte feature row | 38,400 |
| QOC-SVM, 200 references | 0 (the circuit is code) | 6,144 statevector + 2,112-byte chunk | 12,800 of reference rows + 800 of kernel outputs | 691,200 |
| QMOC-SVM, 1,000 landmarks | 0 (same circuit) | 6,144 statevector + 2,112-byte chunk | 3,520 for the 55 support vectors | **8,128,000** |

TinyML’s 68 bytes are 16 int32 weights and one bias. A feature row is 16×4
bytes.

The fidelity and QMOC calls send at most 32 reference rows plus one query
row (33 × 16 float32 = 2,112 bytes) and reuse the same 6,144-byte
statevector. They do not allocate the Gram matrix in secure world.

QMOC-SVM’s 8,128,000 bytes are the host files from this run: Gram
4,000,000, calibration kernel 1,600,000, test kernel 2,400,000, plus the
1,000 landmarks (64,000), 400 calibration rows (25,600), and 600 test rows
(38,400). After the fit, classification uses the 55 support vectors only
(55 × 64 bytes). The earlier fidelity score held a 200×200 Gram (160,000)
and a 600×200 test kernel (480,000), 691,200 bytes with its feature files.
Its 200 training rows all became support vectors, so the post-fit reference
set stays 12,800 bytes.

---

## 5. Accuracy on the shared 600 rows

| Method | Training | Accuracy | Precision | Recall | F1 |
|---|---|---:|---:|---:|---:|
| TinyML, TA | supervised, 4,000 rows | 84.0% | 0.736 | 0.810 | 0.771 |
| **QMOC-SVM, this TA** | one-class, 1,000 normal | **66.2%** | **0.495** | **0.710** | **0.583** |
| QOC-SVM, 3 reps, \([-\pi,\pi]\), 200 refs | one-class | 24.0% | 0.265 | 0.720 | 0.387 |
| QOC-SVM, 3 reps, angles × 0.1, nu=0.05 | one-class | 49.3% | 0.384 | 0.865 | 0.532 |
| Classical RBF one-class, nu=0.05 | one-class, 200 normal | 47.2% | 0.373 | 0.860 | 0.520 |
| Paper Table I, quantum | one-class, unpublished | 87% | 0.88 | 0.87 | 0.86 |
| Paper Table I, classical | unpublished | 73% | 0.81 | 0.73 | 0.65 |

Confusion counts (true normal / false attack / missed attack / caught attack):

| Method | TN | FP | FN | TP |
|---|---:|---:|---:|---:|
| TinyML | 342 | 58 | 38 | 162 |
| QMOC-SVM | 255 | 145 | 58 | 142 |
| QOC-SVM, \([-\pi,\pi]\) | 0 | 400 | 56 | 144 |
| Classical RBF, nu=0.05 | 111 | 289 | 28 | 172 |

QMOC-SVM calls 287 of the 600 rows an attack: 145 false attacks and 142
caught attacks. It accepts 255 of the 400 normal test rows. QOC-SVM accepted
none.

---

## 6. Reading the comparison

On this draw QMOC-SVM is the strongest one-class result measured in the TA.
Accuracy rises from 24.0% to 66.2%, and F1 from 0.387 to 0.583, because
distinct normal rows now have a spread of fidelities and the SVM is no longer
a nearly diagonal kernel. It also sits above the classical RBF one-class
model on these rows (47.2%, F1 0.520).

The memory gap is the same shape as the time gap. TinyML keeps 68 bytes of
weights and classifies a row from that row alone. QMOC-SVM’s secure scratch
is the shared 6,144-byte statevector, but scoring this draw materialized
8,128,000 bytes of kernel values on the host. Keeping only the 55 support
vectors drops the post-fit model to 3,520 bytes of landmark features, still
above TinyML and far below the Gram.

It does not reach TinyML. TinyML sees attack labels during training; QMOC-SVM
does not. It also does not reach Table I. The published 87% / F1 0.86 used an
unpublished training width, `nu`, and gate list, and this run deliberately
uses one repetition and a bandwidth of 0.18 rather than the paper’s three
repetitions at full \([-\pi,\pi]\).
