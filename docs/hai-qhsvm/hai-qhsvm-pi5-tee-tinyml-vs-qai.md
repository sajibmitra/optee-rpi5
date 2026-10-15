# TinyML, QOC-SVM, and QMOC-SVM on the same HAI draw

TinyML, QOC-SVM, and QMOC-SVM ran inside the OP-TEE Trusted Application on the
Raspberry Pi 5. The test rows are the same 600 HAI 20.07 rows. Measurement
detail for TinyML is in
[`hai-qhsvm-pi5-tee-tinyml-output.md`](hai-qhsvm-pi5-tee-tinyml-output.md).
QOC-SVM is in
[`hai-qhsvm-pi5-tee-hai-tables-arXiv_2409.04935.md`](hai-qhsvm-pi5-tee-hai-tables-arXiv_2409.04935.md).
QMOC-SVM, including memory, is in
[`hai-qhsvm-pi5-tee-qmoc-svm.md`](hai-qhsvm-pi5-tee-qmoc-svm.md).

Positive class is attack. The draw is 400 normal + 200 attack (seed 2409),
not the natural ~4% attack rate of the full test capture.

---

## 1. The three models

| Name | Where the math ran | What it is |
|---|---|---|
| TinyML | TA command 7, model 0 | 16-weight logistic regression, milli-units |
| QOC-SVM | TA command `TA_QAI_CMD_QOC_BLOCK` | 8-qubit fidelity, 3 repetitions, 200 normal references, then a host one-class SVM |
| QMOC-SVM | TA command `TA_QAI_CMD_QMOC_BLOCK` | Same circuit, 1 repetition, bandwidth 0.18, 1,000 normal landmarks, `nu` from held-out normals |

TinyML was trained with labels (2,000 normal + 2,000 attack, disjoint from
the test draw). QOC-SVM and QMOC-SVM are one-class: their reference rows are
normal only. The Pi 5 has no quantum processor. Both SVM kernels are classical
simulations of the Cultice et al. circuit (arXiv:2409.04935) on the Cortex-A76.

---

## 2. Accuracy on the shared 600 rows

| Method | Training | Accuracy | Precision | Recall | F1 |
|---|---|---:|---:|---:|---:|
| TinyML, this TA | supervised, 4,000 rows | **84.0%** | **0.736** | **0.810** | **0.771** |
| QMOC-SVM, this TA | one-class, 1,000 normal | **66.2%** | **0.495** | **0.710** | **0.583** |
| QOC-SVM, this TA, angles in \([-\pi,\pi]\), any nu 0.05–0.50 | one-class, 200 normal | 24.0% | 0.265 | 0.720 | 0.387 |
| QOC-SVM, this TA, angles × 0.1, nu=0.05 | one-class, 200 normal | 49.3% | 0.384 | 0.865 | 0.532 |
| Classical RBF one-class, same rows, nu=0.05 | one-class, 200 normal | 47.2% | 0.373 | 0.860 | 0.520 |
| Paper Table I, quantum, 16 features / 8 qubits | one-class, unpublished width and `nu` | 87% | 0.88 | 0.87 | 0.86 |
| Paper Table I, classical, 16 features | unpublished | 73% | 0.81 | 0.73 | 0.65 |

Confusion counts (true normal / false attack / missed attack / caught attack):

| Method | TN | FP | FN | TP |
|---|---:|---:|---:|---:|
| TinyML | 342 | 58 | 38 | 162 |
| QMOC-SVM | 255 | 145 | 58 | 142 |
| QOC-SVM, \([-\pi,\pi]\) | 0 | 400 | 56 | 144 |
| Classical RBF, nu=0.05 | 111 | 289 | 28 | 172 |
| QOC-SVM, ×0.1, nu=0.05 | 123 | 277 | 27 | 173 |

At the paper’s \([-\pi,\pi]\) scaling, QOC-SVM called every normal test row an
attack (off-diagonal \(\exp(K) = 1\)). QMOC-SVM, with one repetition and a
training-set bandwidth, accepts 255 of those 400 normal rows. TinyML, which
sees attack labels during training, accepts 342. None of the three reaches
the published 87% / F1 0.86. The paper does not give the training width,
`nu`, or the exact Figure 4 gate list.

---

## 3. Time inside the TA

| Work | Measured TA time | Per test row |
|---|---:|---:|
| TinyML, 600 rows × 100,000 passes | 989 ms | 16.5 ns |
| QOC-SVM, 600 × 200 kernel pairs | 29,640 ms | 49.4 ms |
| QMOC-SVM, 600 × 1,000 kernel pairs | 50,848 ms | 84.7 ms |

Per row on this board, one secure core:

- One QOC-SVM test row takes about 3.0×10⁶ times the TinyML time.
- One QMOC-SVM test row takes about 5.1×10⁶ times the TinyML time. It uses
  1,000 landmarks instead of 200, and each pair is faster because the circuit
  runs once instead of three times.

A single 600-row TinyML pass is below the 1 ms TEE tick, so
`TEE_GetSystemTime` reports 0 ms for that pass. The nanosecond figure comes
from the 60,000,000-row loop. The SVM times are one real pass of the kernel,
already longer than the clock resolution.

Projecting the measured per-row rates onto the full moving-average test
capture (444,482 rows) gives about 7 ms (TinyML), about 6.1 hours (QOC-SVM
against these 200 references), and about 10.4 hours (QMOC-SVM against these
1,000 landmarks). A kernel against the full 550,682 training rows remains the
multi-year figure in the earlier TEE estimate.

---

## 4. Reading the comparison

The secure-world TinyML detector is a real classifier: fixed-point weights
resident in the TA, HAI rows copied in, attack/normal decisions copied out.
Those decisions match the host integer formula and the float logistic
predictions on every test row.

QOC-SVM is the 3-repetition paper circuit on 200 normal references. On this
split it does not match Table I. QMOC-SVM is the same circuit with the
bandwidth, repetition count, landmark count, and `nu` chosen from normal
training rows. It is the strongest one-class result of the three, and it
still sits below TinyML because TinyML sees attack examples during training.
