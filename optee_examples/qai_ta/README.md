# QAI-OPTEE Trusted Application (`qai_ta`)

Hybrid QAI prototype for Raspberry Pi 5 + OP-TEE, following
`docs/qai-optee-prototype-roadmap.md`.

## Architecture

```text
Normal World (REE)                  TEE (OP-TEE)
Sensor / features  ──TEEC_Invoke──►  QAI TA
                                     • model parameters (resident)
                                     • baseline / TinyML / QAI infer
                                     • optional decrypt (protected path)
Prediction ◄───────────────────────  result + confidence
```

## Build

From the `pi5-optee` repo root (after OP-TEE OS + client are built):

```bash
./optee_examples/qai_ta/scripts/build-qai-ta.sh
```

## Deploy to Pi 5

```bash
./optee_examples/qai_ta/scripts/deploy-qai-ta.sh USER@PI_LAN_IP
```

## Run on Pi

```bash
qai_host                  # Phase 2–4 baseline: expect pred=1 conf=28
qai_host --tinyml         # Phase 5/7 TinyML
qai_host --qai            # Phase 6 quantum-inspired
qai_host --protected --qai
qai_host --bench 200      # Phase 9 REE vs TEE latency
qai_host --ree-compare
qai_host --info
```

Full measurement sweep:

```bash
./optee_examples/qai_ta/scripts/measure.sh 200
```

## Retrain parameters (host / Mac)

```bash
python3 tools/train_tinyml.py
python3 tools/train_qai_hybrid.py
```

Paste emitted C snippets into `ta/model_params.h`, then rebuild.

## Layout

```text
qai_ta/
├── host/main.c              # REE client + timing + REE baseline
├── ta/qai_ta.c              # TA entry + commands
├── ta/inference.c           # secure inference kernels
├── ta/model_params.h        # protected weights / θ / key
├── include/qai_ta.h         # shared ABI
├── tools/train_*.py         # offline TinyML / QAI training
└── scripts/                 # build / deploy / measure
```
