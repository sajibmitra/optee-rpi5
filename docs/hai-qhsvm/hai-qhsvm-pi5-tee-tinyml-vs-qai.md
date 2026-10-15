# TinyML, QOC-SVM, and QMOC-SVM on the same HAI draw

TinyML, QOC-SVM, and QMOC-SVM ran inside the OP-TEE Trusted Application on the
Raspberry Pi 5. QOC-SVM and QMOC-SVM each have an 8-qubit run and a 16-qubit
run. The test rows are the same 600 HAI 20.07 rows. Measurement detail for
TinyML is in
[`hai-qhsvm-pi5-tee-tinyml-output.md`](hai-qhsvm-pi5-tee-tinyml-output.md).
The 8-qubit QOC-SVM comparison with Tables I and II is in
[`hai-qhsvm-pi5-tee-hai-tables-arXiv_2409.04935.md`](hai-qhsvm-pi5-tee-hai-tables-arXiv_2409.04935.md).
QMOC-SVM, both widths, including memory, is in
[`hai-qhsvm-pi5-tee-qmoc-svm.md`](hai-qhsvm-pi5-tee-qmoc-svm.md).

Positive class is attack. The draw is 400 normal + 200 attack (seed 2409),
not the natural ~4% attack rate of the full test capture.

---

## 1. The models

| Name | Where the math ran | What it is |
|---|---|---|
| TinyML | TA command 7, model 0 | 16-weight logistic regression, milli-units |
| QOC-SVM 8q | `TA_QAI_CMD_QOC_BLOCK`, 8 qubits | 16 features, 3 repetitions, angles in \([-\pi,\pi]\), 200 normal references, then a host one-class SVM |
| QMOC-SVM 8q | `TA_QAI_CMD_QMOC_BLOCK`, 8 qubits | Same circuit, 1 repetition, bandwidth 0.18, 1,000 normal landmarks, `nu` from held-out normals |
| QOC-SVM 16q | `TA_QAI_CMD_QOC_BLOCK`, 16 qubits | 32 features, 3 repetitions, angles in \([-\pi,\pi]\), 16 normal references |
| QMOC-SVM 16q | `TA_QAI_CMD_QMOC_BLOCK`, 16 qubits | Same 32 features, 1 repetition, bandwidth 0.12, 32 normal landmarks, `nu` from the same 400 held-out normals |

TinyML was trained with labels (2,000 normal + 2,000 attack, disjoint from
the test draw). The SVM models are one-class: their reference rows are
normal only. The Pi 5 has no quantum processor. The kernels are classical
simulations of the Cultice et al. circuit (arXiv:2409.04935) on the Cortex-A76:
dense-angle RY/RZ and a nearest-neighbour CNOT ring. Eight qubits use two
angles each (16 features). Sixteen qubits use two angles each (32 features).
The first 16 of those 32 tags are the 8-qubit tags, scaled with the same
per-column min/max, so those angle columns match the 8-qubit files before
QMOC-SVM applies its bandwidth.

The 16-qubit landmark counts are smaller than the 8-qubit counts because a
pair takes about 153 ms (3 repetitions) or about 51 ms (1 repetition). A
200-reference 16-qubit QOC-SVM test of these 600 rows would be about 5.1
hours, and a 1,000-landmark 16-qubit QMOC-SVM test about 8.5 hours. The
16-qubit scores below use 16 and 32 landmarks so the Pi run finishes, on the
same 600 test rows.

---

## 2. Accuracy on the shared 600 rows

| Method | Training | Accuracy | Precision | Recall | F1 |
|---|---|---:|---:|---:|---:|
| TinyML, this TA | supervised, 4,000 rows | **84.0%** | **0.736** | **0.810** | **0.771** |
| QMOC-SVM 8q | one-class, 1,000 normal | **66.2%** | **0.495** | **0.710** | **0.583** |
| QOC-SVM 8q, angles in \([-\pi,\pi]\), any nu 0.05–0.50 | one-class, 200 normal | 24.0% | 0.265 | 0.720 | 0.387 |
| QOC-SVM 8q, angles × 0.1, nu=0.05 | one-class, 200 normal | 49.3% | 0.384 | 0.865 | 0.532 |
| QMOC-SVM 16q, scale 0.12, nu=0.01 | one-class, 32 normal | 38.5% | 0.346 | 0.950 | 0.507 |
| QOC-SVM 16q, angles in \([-\pi,\pi]\), any nu 0.05–0.50 | one-class, 16 normal | 23.2% | 0.258 | 0.695 | 0.376 |
| Classical RBF one-class, same 16 columns, nu=0.05 | one-class, 200 normal | 47.2% | 0.373 | 0.860 | 0.520 |
| Paper Table I, quantum, 16 features / 8 qubits | one-class, unpublished width and `nu` | 87% | 0.88 | 0.87 | 0.86 |
| Paper Table I, classical, 16 features | unpublished | 73% | 0.81 | 0.73 | 0.65 |

Confusion counts (true normal / false attack / missed attack / caught attack):

| Method | TN | FP | FN | TP |
|---|---:|---:|---:|---:|
| TinyML | 342 | 58 | 38 | 162 |
| QMOC-SVM 8q | 255 | 145 | 58 | 142 |
| QOC-SVM 8q, \([-\pi,\pi]\) | 0 | 400 | 56 | 144 |
| QMOC-SVM 16q | 41 | 359 | 10 | 190 |
| QOC-SVM 16q, \([-\pi,\pi]\) | 0 | 400 | 61 | 139 |
| Classical RBF, nu=0.05 | 111 | 289 | 28 | 172 |
| QOC-SVM 8q, ×0.1, nu=0.05 | 123 | 277 | 27 | 173 |

At the paper’s \([-\pi,\pi]\) scaling, both QOC-SVM widths called every normal
test row an attack. Off-diagonal fidelity is about 0 (8 qubits, 200
references) and about 0 (16 qubits, 16 references; median \(\exp(K) = 1.000\)).
QMOC-SVM 8q, with one repetition and a training-set bandwidth, accepts 255 of
those 400 normal rows. QMOC-SVM 16q also has a graded kernel (Gram median
fidelity 0.399) but the 32-landmark fit still flags 359 of the 400 normals.
TinyML, which sees attack labels during training, accepts 342. None of these
TA runs reaches the published 87% / F1 0.86. The paper’s Table I has no
16-qubit row. Its widest listed quantum row is 12 qubits / 24 features, and
that row was not run here.

---

## 3. Time inside the TA

| Work | Measured TA time | Per test row |
|---|---:|---:|
| TinyML, 600 rows × 100,000 passes | 989 ms | 16.5 ns |
| QOC-SVM 8q, 600 × 200 kernel pairs | 29,640 ms | 49.4 ms |
| QMOC-SVM 8q, 600 × 1,000 kernel pairs | 50,848 ms | 84.7 ms |
| QOC-SVM 16q, 600 × 16 kernel pairs | 1,472,118 ms | 2.45 s |
| QMOC-SVM 16q, 600 × 32 kernel pairs | 981,759 ms | 1.64 s |

Pair rates on this board, one secure core:

- QOC-SVM 8q: 0.247 ms/pair (3 repetitions, 256 amplitudes).
- QMOC-SVM 8q: 0.085 ms/pair (1 repetition).
- QOC-SVM 16q: 153.3 ms/pair (3 repetitions, 65,536 amplitudes). The 16×16 Gram was 39,255 ms.
- QMOC-SVM 16q: 51.1 ms/pair (1 repetition). The 32×32 Gram was 52,640 ms. Calibration, 400×32, was 654,623 ms.

A single 600-row TinyML pass is below the 1 ms TEE tick, so
`TEE_GetSystemTime` reports 0 ms for that pass. The nanosecond figure comes
from the 60,000,000-row loop. The SVM times are one real pass of the kernel.

Projecting the measured per-row rates onto the full moving-average test
capture (444,482 rows) gives about 7 ms (TinyML), about 6.1 hours (QOC-SVM 8q
against these 200 references), about 10.4 hours (QMOC-SVM 8q against these
1,000 landmarks), about 12.6 days (QOC-SVM 16q against these 16 references),
and about 8.4 days (QMOC-SVM 16q against these 32 landmarks). A kernel against
the full 550,682 training rows remains the multi-year figure in the earlier
8-qubit TEE estimate.

After the qubit-width field was added, an 8-qubit 2×2 block from the saved
Gram matched the new TA with a maximum absolute difference of 0. A 16-qubit
row compared with itself returned \(\exp(K) = 2.718282\).

---

## 4. Reading the comparison

The secure-world TinyML detector is a real classifier: fixed-point weights
resident in the TA, HAI rows copied in, attack/normal decisions copied out.
Those decisions match the host integer formula and the float logistic
predictions on every test row.

QOC-SVM is the 3-repetition circuit at \([-\pi,\pi]\). On this split the
8-qubit and 16-qubit versions both collapse to a nearly diagonal kernel, so
the one-class SVM calls every normal test row an attack. QMOC-SVM 8q is the
strongest one-class result measured here (66.2%, F1 0.583). QMOC-SVM 16q
keeps a spread of fidelities, and it catches 190 of 200 attacks, but 32
landmarks are not enough to hold the calibration false-alarm rate near 5%.
It sits below both QMOC-SVM 8q and the classical RBF model on the 16-feature
columns. All four SVM variants sit below TinyML, which sees attack examples
during training.
