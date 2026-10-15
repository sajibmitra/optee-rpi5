# TinyML HAI inference inside the Trusted Application

A 16-feature logistic TinyML detector was trained on real HAI 20.07 rows and
executed inside the OP-TEE Trusted Application on the Raspberry Pi 5 at
`skmitra@172.20.10.2`.

Training ran on the host. Inference, including the clock, ran in the TA.
There is no GPU and no quantum processor on this board.

---

## 1. Device

| Item | Value |
|---|---|
| Board | Raspberry Pi 5 Model B Rev 1.1 |
| CPU | 4× Cortex-A76 |
| RAM | 2,021,376 kB `MemTotal` |
| Kernel | Linux 6.18.46-v8-16k+, aarch64 |
| TEE client | `qai_hai_infer`, run as root |
| TA UUID | `24173bc2-5143-4d91-92c5-ffae31dc618d` |
| Command | `TA_QAI_CMD_HAI_INFER` (7) |
| Clock | `TEE_GetSystemTime` inside the inference loop (1 ms resolution) |
| Signed TA | 85,152 bytes |

The signed image is the existing QAI TA with this command added. Section sizes
of the ELF that produced the TinyML numbers below: `.text` 57,460,
`.rodata` 4,891, `.data` 440, `.bss` 53,424. That `.bss` includes the 8-qubit
fidelity statevector that lived in the same TA. A later image, used for the
16-qubit QOC-SVM and QMOC-SVM runs, keeps the same command and enlarges
`.bss` to 1,620,144 bytes so a 16-qubit statevector can sit beside TinyML.
The HAI logistic weights themselves are 17 int32 values (16 coefficients and
one bias). The TinyML accuracy and timing in this note were not re-measured
on that larger image.

---

## 2. Dataset and split

Source: HAI 20.07 (`https://github.com/icsdataset/hai`), local copy
`/home/skmit/optee/hai-src/hai-20.07/`. CSVs stay outside this repo.

Host preprocessing (`optee_examples/qai_ta/tools/hai_tee_prepare.py`, seed
2409) matches the earlier fidelity-kernel scoring note:

- 60-sample moving average inside each file.
- Histogram encoding of low-cardinality train columns, then z-score.
- 16 features kept by a depth-8 Gini tree fit on a disjoint labeled slice:
  `P2_VXT03`, `P1_LCV01D`, `P2_SIT01`, `P1_LIT01`, `P1_FT01Z`, `P1_B2004`,
  `P1_PCV01D`, `P1_B3004`, `P3_LCV01D`, `P1_FCV03Z`, `P1_FCV02Z`, `P1_PIT02`,
  `P3_LT01`, `P1_FCV03D`, `P4_ST_TT01`, `P1_PIT01`.

| Role | Rows | Label mix |
|---|---:|---|
| Supervised train | 4,000 | 2,000 normal + 2,000 attack |
| Test | 600 | 400 normal + 200 attack |

The test draw is the same 600 z-scored rows used for the fidelity-kernel
Table I/II note (`classical_query.bin`, `labels.bin`). The 4,000 training
rows are taken from the remainder of that shuffle, after the test slice, so
they do not overlap the test set. Positive class is `attack`.

This test mix is 2:1, the same construction as the earlier TEE note. It is
not the full HAI test capture (444,482 rows after the moving average, 3.94%
attack).

---

## 3. Model inside the TA

TinyML uses milli-units, `QAI_FP_SCALE = 1000`. A host feature \(x\) is
sent as `int32` \(\mathrm{round}(x \times 1000)\). Weights in
`ta/model_hai.h` are \(\mathrm{round}(w \times 1000)\).

**TinyML** (`model = 0`). Logistic regression, scikit-learn 1.9.1,
`class_weight="balanced"`, `max_iter=500`, 16 z-scored inputs. The TA score is

\[
\mathrm{acc} = b \cdot S + \sum_{i=0}^{15} w_i x_i
\]

and the prediction is attack when `acc > 0`.

Quantized weights: bias 2334, and

1859, 1667, −536, 488, −1264, 160, −579, −284, 144, −259, 298, 183, −170, 222, −124, 156.

The 4-feature demo command `qai_host --tinyml` is unchanged.

---

## 4. What the Pi returned

One pass of the 600 test rows, then a timed repeat of 100,000 passes
(60,000,000 row evaluations). Predictions from both runs match the host
fixed-point formula on all 600 rows, and they also match the float
scikit-learn `predict` labels on all 600 rows (0 disagreements).

`TEE_GetSystemTime` reports 0 ms for a single 600-row pass. TinyML finishes
that pass below the 1 ms TEE tick. The rate below is the 100,000-pass loop,
still timed inside the TA and summed across the 19 secure calls (32 rows per
call, last call 24).

| Model | TEE time for 6×10⁷ rows | Time per row | Rows / s |
|---|---:|---:|---:|
| TinyML | 989 ms | 16.5 ns | 6.07×10⁷ |

One 600-row TinyML pass is about 9.9 µs of TA compute. Projecting the measured
per-row time onto the full moving-average test capture (444,482 rows) gives
about 7.3 ms, on one secure core, excluding the Normal World copy of the rows.

---

## 5. Accuracy on the 600-row HAI test draw

Positive class = attack. Counts are true normal, false attack, missed attack,
caught attack.

| Model | Accuracy | Precision | Recall | F1 | Confusion |
|---|---:|---:|---:|---:|---|
| TinyML, TA | 84.0% | 0.736 | 0.810 | 0.771 | 342 / 58 / 38 / 162 |

TinyML called 220 of 600 rows an attack (58 false attacks, 162 true attacks).

This is a supervised detector. It was trained with attack labels. It is not a
one-class SVM, and it is not the published Table I protocol. The comparison
with QOC-SVM and QMOC-SVM is in
[`hai-qhsvm-pi5-tee-tinyml-vs-qai.md`](hai-qhsvm-pi5-tee-tinyml-vs-qai.md).
