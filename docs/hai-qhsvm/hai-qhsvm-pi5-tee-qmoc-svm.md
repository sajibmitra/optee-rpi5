# QMOC-SVM on HAI 20.07, inside the Trusted Application

QMOC-SVM is the fidelity one-class model with the robustness changes applied:
one circuit repetition instead of three, an angle bandwidth chosen from
training pairs, more landmarks than the collapsed QOC-SVM run, and `nu`
chosen on held-out normal rows. Sections 1–6 are the 8-qubit model (16
features, 1,000 landmarks, scale 0.18). Section 7 is the 16-qubit model (32
features, 32 landmarks, scale 0.12). Both kernels ran in the OP-TEE Trusted
Application on the Raspberry Pi 5 at `skmitra@172.20.10.2`, command
`TA_QAI_CMD_QMOC_BLOCK`. The host sets `n_qubits`. The one-class SVM was fit
on the host from those kernel values.

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

TinyML, QOC-SVM, and QMOC-SVM share one signed image. The Pi has 2,021,376 kB
of Normal World RAM. The 8-qubit scores in sections 1–6 were measured on the
smaller image. The 16-qubit scores in section 7 were measured after the
statevector buffers were enlarged to 65,536 amplitudes. That larger `.bss`
stays resident for every command in the current TA, including TinyML and the
8-qubit kernel.

### Image that produced the 8-qubit scores

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

The 32,768-byte heap (`TA_DATA_SIZE`, symbol `ta_heap`) sits inside `.bss`.
On that image the fidelity statevector is 6,144 bytes: `psi_re` and `psi_im`
are 2,048 bytes each, `tmp_re` and `tmp_im` are 1,024 bytes each.

### Image that produced the 16-qubit scores

| Region | Bytes |
|---|---:|
| Signed `.ta` file | 85,160 |
| `.text` | 57,968 |
| `.rodata` | 4,895 |
| `.data` | 448 |
| `.bss` | 1,620,144 |
| ELF span through the end of `.bss` | 1,699,440 |
| Stack, `TA_STACK_SIZE`, added on each call | 4,096 |
| Reserved for one TA call | **1,703,536** |

`.bss` is not stored in the signed file, which is why the file grew by only
8 bytes. The 16-qubit scratch is 1,572,864 bytes: two statevectors of 65,536
doubles and two half-width temporaries of 32,768 doubles. An 8-qubit call
on this image still walks only the first 256 amplitudes. The heap remains
32,768 bytes inside the same `.bss`.

### Bytes that belong to each model

Weights are the `.rodata` arrays. “One new row” is the Normal World state
required after the fit, when a single HAI row is classified. The kernel
matrices are the files this experiment actually held while producing the
scores above.

| Model | Weights in the TA | TA scratch for one call | One new row after the fit | Matrices held for this score |
|---|---:|---:|---:|---:|
| TinyML | 68 | 2,048-byte feature chunk | 64-byte feature row | 38,400 |
| QOC-SVM 8q, 200 references | 0 (the circuit is code) | 6,144 statevector + 2,112-byte chunk | 12,800 of reference rows + 800 of kernel outputs | 691,200 |
| QMOC-SVM 8q, 1,000 landmarks | 0 (same circuit) | 6,144 statevector + 2,112-byte chunk | 3,520 for the 55 support vectors | **8,128,000** |
| QOC-SVM 16q, 16 references | 0 | 1,572,864 statevector + 4,224-byte chunk | 2,048 of reference rows + 64 of kernel outputs | 118,272 |
| QMOC-SVM 16q, 32 landmarks | 0 | 1,572,864 statevector + 4,224-byte chunk | 2,304 for the 18 support vectors | 264,192 |

TinyML’s 68 bytes are 16 int32 weights and one bias. A feature row is 16×4
bytes.

The 8-qubit calls send at most 32 reference rows plus one query row
(33 × 16 float32 = 2,112 bytes) and, on the image that produced those
scores, reuse the 6,144-byte statevector. The 16-qubit calls send
33 × 32 float32 = 4,224 bytes and use the 1,572,864-byte statevector.
Neither width allocates the Gram matrix in secure world.

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
| **QMOC-SVM 8q, this TA** | one-class, 1,000 normal | **66.2%** | **0.495** | **0.710** | **0.583** |
| QMOC-SVM 16q, scale 0.12, nu=0.01 | one-class, 32 normal | 38.5% | 0.346 | 0.950 | 0.507 |
| QOC-SVM 8q, 3 reps, \([-\pi,\pi]\), 200 refs | one-class | 24.0% | 0.265 | 0.720 | 0.387 |
| QOC-SVM 16q, 3 reps, \([-\pi,\pi]\), 16 refs | one-class | 23.2% | 0.258 | 0.695 | 0.376 |
| QOC-SVM 8q, 3 reps, angles × 0.1, nu=0.05 | one-class | 49.3% | 0.384 | 0.865 | 0.532 |
| Classical RBF one-class, nu=0.05 | one-class, 200 normal | 47.2% | 0.373 | 0.860 | 0.520 |
| Paper Table I, quantum | one-class, unpublished | 87% | 0.88 | 0.87 | 0.86 |
| Paper Table I, classical | unpublished | 73% | 0.81 | 0.73 | 0.65 |

Confusion counts (true normal / false attack / missed attack / caught attack):

| Method | TN | FP | FN | TP |
|---|---:|---:|---:|---:|
| TinyML | 342 | 58 | 38 | 162 |
| QMOC-SVM 8q | 255 | 145 | 58 | 142 |
| QMOC-SVM 16q | 41 | 359 | 10 | 190 |
| QOC-SVM 8q, \([-\pi,\pi]\) | 0 | 400 | 56 | 144 |
| QOC-SVM 16q, \([-\pi,\pi]\) | 0 | 400 | 61 | 139 |
| Classical RBF, nu=0.05 | 111 | 289 | 28 | 172 |

QMOC-SVM 8q calls 287 of the 600 rows an attack: 145 false attacks and 142
caught attacks. It accepts 255 of the 400 normal test rows. QOC-SVM at
\([-\pi,\pi]\), both qubit widths, accepted none. The 16-qubit QMOC-SVM
counts are in section 7.

---

## 6. Reading the comparison

On this draw QMOC-SVM 8q is the strongest one-class result measured in the TA.
Accuracy rises from 24.0% to 66.2%, and F1 from 0.387 to 0.583, because
distinct normal rows now have a spread of fidelities and the SVM is no longer
a nearly diagonal kernel. It also sits above the classical RBF one-class
model on these rows (47.2%, F1 0.520).

The memory gap is the same shape as the time gap. TinyML keeps 68 bytes of
weights and classifies a row from that row alone. On the image that produced
this 8-qubit score, QMOC-SVM’s secure scratch is the shared 6,144-byte
statevector, but scoring this draw materialized 8,128,000 bytes of kernel
values on the host. Keeping only the 55 support vectors drops the post-fit
model to 3,520 bytes of landmark features, still above TinyML and far below
the Gram. The current TA image reserves the 16-qubit statevector instead;
that figure is in section 4.

It does not reach TinyML. TinyML sees attack labels during training; QMOC-SVM
does not. It also does not reach Table I. The published 87% / F1 0.86 used an
unpublished training width, `nu`, and gate list, and this run deliberately
uses one repetition and a bandwidth of 0.18 rather than the paper’s three
repetitions at full \([-\pi,\pi]\).

---

## 7. Sixteen qubits, 32 features

The circuit is the same RY/RZ plus nearest-neighbour CNOT ring, with
`n_qubits = 16` and one repetition. Each qubit still takes two angles, so a
row has 32 features: the original 16 tags plus the next 16 by the same Gini
order. Column min/max are still taken from the 200-row QOC-SVM reference
set, and the first 16 angle columns match the 8-qubit files before the
bandwidth multiply.

A 200-reference or 1,000-landmark Gram at this width does not finish in a
short Pi session. One pair measured 51.1 ms, so 600 test rows against 1,000
landmarks would be about 8.5 hours. This run keeps the same 600 test rows
and the same 400 calibration normals, and cuts the landmarks to the first
32 of the 1,000.

### Bandwidth and `nu`

On 16 of those training landmarks the TA evaluated eight scales. The scale
whose off-diagonal median fidelity is inside \([0.1, 0.5]\) and closest to
0.30 is **0.12** (median fidelity 0.413). Scale 0.18 is also inside the
band (0.135) and is farther from 0.30. The same 0.12 scale on the 32×32
Gram has off-diagonal median fidelity **0.399**. The diagonal fidelity is
1.000.

| Scale | Median fidelity, 16 training rows |
|---:|---:|
| 1.00 | 0.000 |
| 0.50 | 0.000 |
| 0.25 | 0.020 |
| 0.18 | 0.135 |
| **0.12** | **0.413** |
| 0.08 | 0.681 |
| 0.05 | 0.863 |
| 0.03 | 0.950 |

`nu` was then chosen so the fraction of the 400 calibration normals flagged
as attack is as close as possible to 5%. No value in the sweep got near 5%.
The three closest ties are 0.630, and the smaller `nu` is the one reported.

| nu | Calibration false-alarm rate | Support vectors |
|---:|---:|---:|
| **0.01** | **0.630** | **18** |
| 0.02 | 0.632 | 18 |
| 0.05 | 0.630 | 18 |
| 0.10 | 0.632 | 18 |
| 0.20 | 0.630 | 18 |

`nu = 0.01` is the reported fit. The other four values produce a slightly
different test labeling (42 true normal, 358 false attack, 11 missed, 189
caught).

### Time

| Kernel | Pairs | TEE time | ms / pair |
|---|---:|---:|---:|
| Bandwidth sweep, 8 scales × 16×16 | 2,048 | 104,791 ms | 51.2 |
| Gram, 32×32 | 1,024 | 52,640 ms | 51.4 |
| Calibration, 400×32 | 12,800 | 654,623 ms | 51.1 |
| Test, 600×32 | 19,200 | 981,759 ms | 51.1 |
| Gram + calibration + test | 33,024 | **1,689 s** | 51.1 |

One test row against the 32 landmarks takes **1.64 s** of TA time.

### Score on the shared 600 rows

Accuracy 38.5%, precision 0.346, recall 0.950, F1 0.507. Confusion counts
are 41 true normal, 359 false attack, 10 missed attack, 190 caught attack.
The kernel is graded, unlike QOC-SVM 16q at \([-\pi,\pi]\) (23.2%, F1 0.376,
every normal called an attack). It does not match QMOC-SVM 8q (66.2%, F1
0.583) and it does not match Table I. Table I has no 16-qubit row.

Post-fit state on the host is 18 support vectors, 2,304 bytes of landmark
features. The kernel files for this score are 264,192 bytes, counting the
Gram, the calibration kernel, the test kernel, and the three feature files.
