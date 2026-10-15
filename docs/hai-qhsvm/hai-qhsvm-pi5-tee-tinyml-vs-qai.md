# TinyML and QAI on the same HAI draw

Both new models ran inside the OP-TEE Trusted Application on the Raspberry Pi 5.
The test rows are the same 600 HAI 20.07 rows already scored with the 8-qubit
fidelity kernel. Measurement detail for the new models is in
[`hai-qhsvm-pi5-tee-tinyml-output.md`](hai-qhsvm-pi5-tee-tinyml-output.md).
The fidelity-kernel run is in
[`hai-qhsvm-pi5-tee-hai-tables-arXiv_2409.04935.md`](hai-qhsvm-pi5-tee-hai-tables-arXiv_2409.04935.md).

Positive class is attack. The draw is 400 normal + 200 attack (seed 2409),
not the natural ~4% attack rate of the full test capture.

---

## 1. Three different “QAI” objects

| Name | Where the math ran | What it is |
|---|---|---|
| TinyML | TA command 7, model 0 | 16-weight logistic regression, milli-units |
| QAI pairwise | TA command 7, model 1 | Same logistic form plus 16 adjacent products \(\gamma_i x_i x_{i+1}\) |
| QAI fidelity | TA command `TA_QAI_CMD_KERNEL_BLOCK` | 8-qubit statevector, Hilbert–Schmidt fidelity, \(\exp(K)\), then a host one-class SVM |

The pairwise model is the quantum-inspired integer kernel already used by
`qai_host --qai`, widened from 4 demo features to these 16 HAI tags. The
fidelity model is the circuit from Cultice et al., arXiv:2409.04935, simulated
on the Cortex-A76 inside the TA. The Pi 5 has no quantum processor.

TinyML and QAI pairwise were trained with labels (2,000 normal + 2,000 attack,
disjoint from the test draw). The fidelity model is one-class: its 200
reference rows are normal only. A higher supervised accuracy is expected if
the features carry label signal, and it is not a like-for-like replacement of
the paper’s one-class SVM.

---

## 2. Accuracy on the shared 600 rows

| Method | Training | Accuracy | Precision | Recall | F1 |
|---|---|---:|---:|---:|---:|
| TinyML, this TA | supervised, 4,000 rows | **84.0%** | **0.736** | **0.810** | **0.771** |
| QAI pairwise, this TA | supervised, 4,000 rows | **85.7%** | **0.762** | **0.830** | **0.794** |
| QAI fidelity, this TA, angles in \([-\pi,\pi]\), any nu 0.05–0.50 | one-class, 200 normal | 24.0% | 0.265 | 0.720 | 0.387 |
| Classical RBF one-class, same rows, nu=0.05 | one-class, 200 normal | 47.2% | 0.373 | 0.860 | 0.520 |
| QAI fidelity, this TA, angles × 0.1, nu=0.05 | one-class, 200 normal | 49.3% | 0.384 | 0.865 | 0.532 |
| Paper Table I, quantum, 16 features / 8 qubits | one-class, unpublished width and `nu` | 87% | 0.88 | 0.87 | 0.86 |
| Paper Table I, classical, 16 features | unpublished | 73% | 0.81 | 0.73 | 0.65 |

Confusion counts (true normal / false attack / missed attack / caught attack):

| Method | TN | FP | FN | TP |
|---|---:|---:|---:|---:|
| TinyML | 342 | 58 | 38 | 162 |
| QAI pairwise | 348 | 52 | 34 | 166 |
| QAI fidelity, \([-\pi,\pi]\) | 0 | 400 | 56 | 144 |
| Classical RBF, nu=0.05 | 111 | 289 | 28 | 172 |
| QAI fidelity, ×0.1, nu=0.05 | 123 | 277 | 27 | 173 |

On this draw the pairwise term is a small gain over plain TinyML: +1.7 points
of accuracy and +0.023 of F1 (four fewer false attacks, four more caught
attacks). Both supervised TA models sit far above the in-TA fidelity kernel.
At the paper’s \([-\pi,\pi]\) scaling that kernel called every normal test row
an attack (off-diagonal \(\exp(K) = 1\)). Scaling angles by 0.1, which is not
the paper’s normalization, brings the fidelity result up to the classical RBF
result on these same rows (49.3% vs 47.2%). Neither one-class run reaches the
supervised TA models or the published 87% / F1 0.86.

The published Table I numbers were not reproduced. The paper does not give the
training width, `nu`, or the exact Figure 4 gate list. The supervised models
also answer a different question: they see attack examples during training.

---

## 3. Time inside the TA

| Work | Measured TA time | Per test row |
|---|---:|---:|
| TinyML, 600 rows × 100,000 passes | 989 ms | 16.5 ns |
| QAI pairwise, same loop | 4,308 ms | 71.8 ns |
| QAI fidelity, 600 × 200 kernel pairs | 29,082 ms | 48.4 ms |

Per row on this board, one secure core:

- QAI pairwise takes about 4.4× the TinyML time (71.8 ns vs 16.5 ns).
- One fidelity test row, compared with the 200 normal references, takes about
  2.9×10⁶ times the TinyML time.

A single 600-row TinyML or QAI pairwise pass is below the 1 ms TEE tick, so
`TEE_GetSystemTime` reports 0 ms for that pass. The nanosecond figures come
from the 60,000,000-row loops. The fidelity time is one real pass of the
600×200 kernel, already longer than the clock resolution.

Projecting the measured per-row rates onto the full moving-average test
capture (444,482 rows) gives about 7 ms (TinyML), about 32 ms (QAI pairwise),
and about 6.0 hours (fidelity against these 200 references). The fidelity
projection is only the kernel against this subset of training rows. A kernel
against the full 550,682 training rows remains the multi-year figure in the
earlier TEE estimate.

---

## 4. Reading the comparison

The secure-world TinyML detector is a real classifier: fixed-point weights
resident in the TA, HAI rows copied in, attack/normal decisions copied out.
Those decisions match the host integer formula and the float logistic
predictions on every test row.

QAI pairwise is the same kind of object with a quadratic feature map. On this
HAI draw it is slightly more accurate and about four times slower than TinyML,
and both finish a 600-row batch in well under a millisecond of TA time.

QAI fidelity is the paper circuit, also executed in the TA, and it is the
expensive one. On this split it does not match Table I, and a supervised
linear model on the same 16 z-scored tags separates the classes more cleanly
than that kernel. Closing the gap to the published 87% requires the missing
training width, `nu`, and gate list, not a faster integer dot product.
