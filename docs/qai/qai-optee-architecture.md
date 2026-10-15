# QAI-OPTEE Prototype Architecture (Phase 10)

## Split of trust

| Component | World | Role |
| --------- | ----- | ---- |
| Sensor / feature extraction | REE | Collect and normalize inputs |
| `qai_host` | REE | `TEEC_*` client, timing, optional encrypt |
| Model parameters (w, θ, γ, key) | TEE | Resident in `qai_ta` only |
| Inference kernels | TEE | Baseline / TinyML / QAI / protected |
| Prediction + confidence | returned to REE | Result of secure inference |

## Commands

| Cmd | Purpose |
| --- | ------- |
| `INFER_BASELINE` | Weighted sum C model (demo: pred=1, conf=28) |
| `INFER_TINYML` | Logistic regression (fixed-point) |
| `INFER_QAI` | Quantum-inspired linear + pairwise terms |
| `INFER_PROTECTED` | XOR-decrypt features in TA, then infer |
| `GET_INFO` | Model size / stack / heap hints |

## Security claim (research)

Sensitive model parameters and (optionally) plaintext features are handled
inside OP-TEE. The Normal World supplies features (or ciphertext) and receives
prediction/confidence without reading TA-resident weights.

## Measurement

On device:

```bash
qai_host --bench 200
qai_host --ree-compare
# or
./optee_examples/qai_ta/scripts/measure.sh 200
```

Compare REE vs TEE latency, model param bytes (`--info`), and accuracy of the
host-trained models (`tools/train_*.py`).
