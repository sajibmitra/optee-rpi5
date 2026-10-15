# HAI 20.07 scored in the Trusted Application

The fidelity kernel for the 16-feature, 8-qubit model in Cultice et al.,
arXiv:2409.04935, was evaluated on real HAI 20.07 rows **inside the OP-TEE
Trusted Application** on the Raspberry Pi 5 at `skmitra@172.20.10.2`.
The one-class SVM and the accuracy numbers were then computed on the host
from those kernel values. This is the comparison against Table I and Table II
of [`2409.04935v1.pdf`](2409.04935v1.pdf).

The published table was **not** reproduced. On this run the secure-world
kernel does not separate normal and attack rows at the rates in Table I.

---

## 1. Dataset that was downloaded

Source: `https://github.com/icsdataset/hai`, directory `hai-20.07`
(the bug-fixed HAI 1.0 release named in Section III of the paper).
Local copy: `/home/skmit/optee/hai-src/hai-20.07/`. The CSVs are gzipped in
that repository. They were not committed into this repo.

| File | Data rows | Hours at 1 Hz |
|---|---:|---:|
| `train1.csv.gz` | 309,600 | 86.0 |
| `train2.csv.gz` | 241,200 | 67.0 |
| `test1.csv.gz` | 291,600 | 81.0 |
| `test2.csv.gz` | 153,000 | 42.5 |

After a 60-sample moving average inside each file: **550,682** training rows
and **444,482** test rows. The test `attack` column is 1 on **17,527** rows,
**3.94%**, which matches the paper’s “about 4%”. The training files are not
entirely unlabeled-normal: **776** training rows have `attack=1`. Those rows
were excluded from the one-class SVM training set. The paper describes the
training capture as normal operation.

Columns used as features: the 59 process tags between `time` and `attack`.
`attack_P1`, `attack_P2`, and `attack_P3` were not used as inputs. The label
for scoring is `attack`.

---

## 2. What ran in the secure world

Command `TA_QAI_CMD_KERNEL_BLOCK`, client `qai_hai_kernel`. Each call sends
real feature rows and returns \(\exp(K)\) from the same 8-qubit statevector
used in the earlier TEE timing note. The TEE clock is `TEE_GetSystemTime`
inside the loop. There is no quantum processor and no GPU.

Preprocessing on the host, following Section IV-A, before the rows were sent:

1. Moving average, window 60, per CSV.
2. Columns with at most 8 distinct training values replaced by their training
   frequency.
3. Z-score using the training mean and standard deviation.
4. Decision tree (`max_depth=8`, Gini) fit on 2,000 normal and 2,000 attack
   **test** rows. Those rows were then excluded from the scored test set.
5. Top 16 features by Gini importance:
   `P2_VXT03`, `P1_LCV01D`, `P2_SIT01`, `P1_LIT01`, `P1_FT01Z`, `P1_B2004`,
   `P1_PCV01D`, `P1_B3004`, `P3_LCV01D`, `P1_FCV03Z`, `P1_FCV02Z`, `P1_PIT02`,
   `P3_LT01`, `P1_FCV03D`, `P4_ST_TT01`, `P1_PIT01`.
6. Those 16 columns scaled to \([-\pi, \pi]\) with the training min and max.
   That is the normalization the paper states for the angle embedding.

Scored subset, seed 2409. The full test kernel would be the 2.35-year TEE
job already estimated, so this is a draw from the files, not every second:

| Role | Rows |
|---|---|
| One-class training | 200 normal rows from the train files |
| Scored test, normal | 400 |
| Scored test, attack | 200 |

The 2:1 normal-to-attack test mix is the mix drawn in Figure 5 (1,000 normal
and 500 attack), at a smaller count. It is **not** the 3.94% base rate of the
full test files. Accuracy on this mix is not comparable to accuracy on the
raw 4% mix without saying so.

### TEE time for this subset

| Kernel | Pairs | TEE time | ms / pair |
|---|---:|---:|---:|
| Train Gram, 200×200 | 40,000 | 9,647 ms | 0.241 |
| Test kernel, 600×200 | 120,000 | 29,082 ms | 0.242 |
| Total | 160,000 | **38.7 s** | 0.242 |

Every diagonal entry was **2.718282**, which is \(e^{1}\) in float32. The
inverse is correct on these HAI rows. Off-diagonal entries of the Gram matrix
sat on **1.0** (fidelity about 0). Distinct rows, after the \([-\pi,\pi]\)
map, are far apart in angle: the nearest training pair still has an L1 gap of
2.94 radians. A probe of that pair inside the TA returned fidelity **0.0028**.
The same row with one feature shifted by 0.05 returned fidelity **0.998**.
The circuit is working. At the paper’s stated angle range it treats typical
HAI pairs as orthogonal.

---

## 3. Scores

Positive class = attack. One-class SVM from scikit-learn 1.9.1.
`predict == -1` is counted as attack. The training Gram was symmetrized and
its diagonal set to \(e\). The paper does not publish `nu`. Three values are
reported rather than one value chosen after looking at the test labels.

### 3.1 Quantum kernel from the TA, angles in \([-\pi,\pi]\)

All four `nu` values produced the same predictions. All 200 training rows
became support vectors, which is what a nearly diagonal kernel does.

| | Accuracy | Precision | Recall | F1 |
|---|---:|---:|---:|---:|
| This TEE run, any of nu = 0.05, 0.10, 0.20, 0.50 | **24.0%** | **0.265** | **0.720** | **0.387** |

Confusion matrix, rows true normal/attack, columns predicted normal/attack:

| | Pred. normal | Pred. attack |
|---|---:|---:|
| True normal (400) | 0 | 400 |
| True attack (200) | 56 | 144 |

Every normal test row was called an attack. Recall is only 0.72 because 56
attack rows were called normal. That is not a calibrated detector. It is a
kernel with no overlap between distinct points, so points that are not copies
of the 200 training rows fall outside the model, normal and attack alike.

### 3.2 Same rows, classical one-class SVM, RBF kernel

Features are the same 16 z-scored columns, before the \([-\pi,\pi]\) map.
`gamma="scale"`.

| nu | Accuracy | Precision | Recall | F1 | Support vectors |
|---:|---:|---:|---:|---:|---:|
| 0.05 | 47.2% | 0.373 | 0.860 | 0.520 | 43 |
| 0.10 | 46.7% | 0.371 | 0.865 | 0.520 | 44 |
| 0.20 | 45.0% | 0.365 | 0.880 | 0.516 | 58 |

At nu = 0.05 the matrix is 111 true normal, 289 false attack, 28 missed
attacks, 172 caught attacks.

### 3.3 Sensitivity: the same TA kernel with angles multiplied by 0.1

This is **not** the paper’s normalization. It is a check that the TA can
return a graded kernel when angles are smaller. Off-diagonal mean of
\(\exp(K)\) was 1.23 with standard deviation 0.27, instead of a flat 1.0.
TEE time was 9,672 ms for the Gram and 28,886 ms for the test kernel.

| nu | Accuracy | Precision | Recall | F1 |
|---:|---:|---:|---:|---:|
| 0.05 and 0.10 | **49.3%** | **0.384** | **0.865** | **0.532** |
| 0.20 | 47.3% | 0.375 | 0.870 | 0.524 |

At nu = 0.05: 123 true normal, 277 false attack, 27 missed attacks, 173
caught attacks. This is the same operating region as the classical RBF model
on these rows, not the region of Table I.

---

## 4. Assessment against Table I

Table I in the paper, 16-feature block (their best quantum row and the
matching classical row):

| Method | Features | Accuracy | Precision | Recall | F1 |
|---|---|---:|---:|---:|---:|
| Quantum, paper | 16 (8 qubits) | 87% | 0.88 | 0.87 | 0.86 |
| Classical, paper | 16 | 73% | 0.81 | 0.73 | 0.65 |
| Quantum, this TA, \([-\pi,\pi]\) | 16 (8 qubits) | 24.0% | 0.265 | 0.720 | 0.387 |
| Classical RBF, this split, nu=0.05 | 16 | 47.2% | 0.373 | 0.860 | 0.520 |
| Quantum, this TA, angles × 0.1, nu=0.05 | 16 (8 qubits) | 49.3% | 0.384 | 0.865 | 0.532 |

The paper’s other quantum rows were not re-run here: 8 features / 4 qubits
(86%, F1 0.85) and 24 features / 12 qubits (82%, F1 0.82). The TA statevector
used for this measurement is 8 qubits, which is the row Table I and Table II
both mark as their result.

What the comparison supports:

- The secure-world 8-qubit circuit does run on HAI rows, and identical rows
  return \(e^{1}\).
- Under the normalization written in Section IV-B, fidelity between distinct
  rows in this subset collapses, and the one-class SVM does not reach the
  Table I quantum numbers. The gap is 63 points of accuracy and 0.47 of F1.
- The classical column on this same split also misses the Table I classical
  numbers (73% and F1 0.65 versus 47% and F1 0.52). The miss is therefore not
  only the quantum kernel. The paper does not publish the training width,
  the test width, `nu`, the RBF `gamma`, or the exact gate list in Figure 4.
- Shrinking the angles so the kernel has a dynamic range lifts the TA result
  to about the classical RBF result on these rows. It still does not reach
  87% or F1 0.86.
- Figure 5’s picture of graded fidelity between HAI samples is not what this
  gate schedule produces at \([-\pi,\pi]\). Either their feature map is milder
  than the three-repetition schedule implemented here, or their scaling does
  not place typical pairs radians apart.

These percentages are for 600 labeled test rows. They are not a claim about
the full 444,482-row test file.

---

## 5. Assessment against Table II

Table II compares published quantum anomaly detectors. Only the last row is
HAI. The others use different datasets, so their metrics are not a score on
this Pi run. They are listed so the TEE result can sit next to the same
columns the paper uses.

| Author and year | Algorithm | Dataset | Qubits | Dimensions | Metrics in the paper | This TEE run on HAI |
|---|---|---|---:|---:|---|---|
| Gouveia et al., 2020 | QSVM | NF-UNSW-NB15 | 16 | 16 | Acc 64% | not this dataset |
| Correa-Jullian et al., 2022 | QSVM | wind-turbine pitch | 8 | 16 | Acc 88.8%, F1 0.893 | not this dataset |
| Tscharke et al., 2023 | QSVR | KDD | 5 | 5 | Acc 82.0%, F1 0.78 | not this dataset |
| Wang et al., 2023 | QHDNN | Fashion-MNIST | 16 | 16 | AUC 88.24 | not this dataset |
| Wang et al., 2023 | QHDNN | MNIST | 16 | 16 | AUC 89.41 | not this dataset |
| Kukliansky et al., 2024 | QNN | NF-UNSW-NB15 | 16 | 16 | F1 0.86 | not this dataset |
| Cultice et al., 2024, Table II “Our Work” | QOC-SVM | HAI | 8 | 16 | Acc 87.0%, F1 0.86 | **Acc 24.0%, F1 0.387** at \([-\pi,\pi]\); **Acc 49.3%, F1 0.532** if angles are scaled by 0.1 |

Against the only HAI row in Table II, this secure-world measurement is lower
on both accuracy and F1. It does not confirm the 87% / 0.86 claim. It also
does not refute it for their unpublished sample and their unpublished circuit
listing. It does show that an 8-qubit fidelity one-class SVM, executed in
this TA on a 200/600 HAI draw with the preprocessing in Section IV-A, does
not by itself produce that claim.

The 8-qubit, 16-dimension operating point is the same point Correa-Jullian
et al. used on a different dataset (reported Acc 88.8%, F1 0.893). This HAI
run is not evidence about that wind-turbine result.

---

## 6. Limits

- Kernel values are from the Pi’s Trusted Application. The SVM fit and the
  metric arithmetic ran on the host with scikit-learn. That split matches the
  paper: the quantum step builds the kernel, and scikit-learn solves the SVM.
- Train width 200 and test width 600 are a compute limit (38.7 s of TEE time
  for the literal angle map), not a width printed in the paper.
- `nu`, the decision-tree depth, and the exact Figure 4 gates are not in the
  PDF. The gates here are the schedule already checked by the \(e^{1}\)
  self-test.
- 4-qubit and 12-qubit rows of Table I were not executed.
- No number above was taken from the Normal World NumPy timing, and none of
  them is the 10.8 ms integer `qai_infer_qai` command.
