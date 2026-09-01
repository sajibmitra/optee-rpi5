# QAI-OPTEE Prototype Roadmap (Raspberry Pi 5)
  Since OP-TEE is successfully running on the Raspberry Pi 5, the next stage is to
  move from infrastructure to a **measurable QAI-OPTEE prototype**.
  **Important principle:** do **not** start by putting a full Qiskit/PennyLane
  stack inside a Trusted Application (TA). OP-TEE TAs should remain small,
  deterministic, and lightweight. For this research, the first architecture should
  be **Hybrid QAI**.
  ---
  ## Hybrid QAI architecture (first target)
  ```text
                      Raspberry Pi 5
  ┌─────────────────────────────────────────────────────────────┐
  │                     Normal World (REE)                      │
  │                                                             │
  │  Sensor/Input → Feature Extraction → QAI Model Parameters  │
  │                              │                              │
  │                              │ TEEC_InvokeCommand()         │
  │                              ▼                              │
  │                  ┌──────────────────────┐                   │
  │                  │      OP-TEE TEE      │                   │
  │                  │                      │                   │
  │                  │   TinyML/QAI TA      │                   │
  │                  │                      │                   │
  │                  │  • secure features   │                   │
  │                  │  • inference         │                   │
  │                  │  • model parameters  │                   │
  │                  │  • result protection │                   │
  │                  └──────────┬───────────┘                   │
  │                             │                               │
  │                             ▼                               │
  │                    Prediction + Confidence                  │
  └─────────────────────────────────────────────────────────────┘
  ```
  ---
  ## Recommended implementation plan
  ### Phase 1 — Freeze the working OP-TEE environment
  This milestone is already achieved.
  Target chain:
  ```text
  RPi5
    ↓
  OP-TEE Core
    ↓
  Secure TA
    ↓
  Normal World Client
    ↓
  TEE_InvokeCommand()
    ↓
  Result returned
  ```
  Validate with existing tools:
  ```bash
  xtest
  ```
  and a simple TA (for example `hello_world`).
  **Research milestone #1:**
  > Raspberry Pi 5 successfully executes an OP-TEE Trusted Application and
  > establishes REE↔TEE communication.
  ---
  ### Phase 2 — Create a clean QAI-OPTEE TA
  Create a dedicated TA under:
  ```text
  ~/pi5-optee/optee_examples/qai_ta/
  ```
  Do **not** keep modifying `hello_world`.
  Recommended structure:
  ```text
  qai_ta/
  ├── host/
  │   ├── main.c
  │   └── Makefile
  ├── ta/
  │   ├── qai_ta.c
  │   ├── user_ta_header_defines.h
  │   ├── sub.mk
  │   └── Makefile
  ├── include/
  │   └── qai_ta.h
  ├── CMakeLists.txt
  └── Makefile
  ```
  The first TA should perform only a simple C inference.
  Example flow:
  ```text
  Input:
  [10, 20, -5, 3]

          ↓

  QAI TA

          ↓

  Feature calculation
          ↓
  Weighted model
          ↓

  Prediction = 1
  Confidence = 28

  This is the **baseline QAI/ML execution inside the TEE**.
  ---
  ### Phase 3 — Implement inference inside the TA
  Do not introduce quantum computing yet.
  First implement something like:
  ```c
  prediction = model_inference(input);
  confidence = calculate_confidence(input);
  ```
  Example model:
  ```text
  x1 = 10
  x2 = 20
  x3 = -5
  x4 = 3

  model:
  w1, w2, w3, w4
  bias

  score =
      w1*x1 +
      w2*x2 +
      w3*x3 +
      w4*x4 +
      bias

  Then:
  ```text
  score > threshold
          ↓
  prediction = 1
  ```
  This provides a **real inference workload**, not only TA communication.
  ---
  ### Phase 4 — Test REE → TA → REE
  The Normal World application should do:
  ```c
  TEEC_InitializeContext()
          ↓
  TEEC_OpenSession()
          ↓
  prepare input
          ↓
  TEEC_InvokeCommand()
          ↓
  receive prediction
          ↓
  TEEC_CloseSession()
  ```
  Target output:
  ```text
  ================================
   QAI-OPTEE Raspberry Pi 5 Test
  ================================

  Input:
    [10, 20, -5, 3]

  Sending data to OP-TEE...

  [TEE] QAI inference started
  [TEE] Input validated
  [TEE] Inference completed

  Prediction : 1
  Confidence : 28

  TEE execution time : xxx us

  This becomes the first **tangible experimental result**.
  ---
  ### Phase 5 — Move from dummy inference to TinyML
  Once C inference works, train a small model on a Mac (or other host).
  Workflow:
  ```text
                      Mac
                       │
               Train TinyML model
                       │
                       ▼
                model parameters
                       │
                       ▼
                 Raspberry Pi 5
                       │
                Normal World
                       │
                       ▼
                    OP-TEE
                       │
                       ▼
                   QAI TA
  ```
  First real model recommendation:
  - **Logistic regression**, or
  - a **tiny neural network**
  Avoid large networks initially.
  Why:
  - model size is measurable
  - inference time is measurable
  - memory consumption is measurable
  - secure execution is demonstrable
  - accuracy is comparable
  - REE vs TEE performance is comparable
  ---
  ### Phase 6 — Introduce the "Q" in QAI
  Do **not** initially attempt:
  ```text
  Qiskit
     ↓
  Raspberry Pi
     ↓
  OP-TEE TA
  ```
  Use a **hybrid quantum-classical model** instead.
  Example:
  ```text
  Classical feature extraction
            ↓
         4 features
            ↓
   Quantum-inspired / quantum model
            ↓
        classification
  ```
  The Mac can initially perform quantum training/simulation with Qiskit or
  PennyLane.
  Then extract a compact parameter set:
  ```text
  θ1
  θ2
  θ3
  θ4
  ...
  ```
  and deploy a lightweight inference representation to the Pi.
  ---
  ### Phase 7 — Put the security-sensitive QAI component inside OP-TEE
  This is the key research architecture.
  **Normal World:**
  ```text
  Sensor
    ↓
  Feature extraction
    ↓
  QAI input
  ```
  **TEE:**
  ```text
               OP-TEE
                  │
          ┌───────▼───────┐
          │   QAI TA      │
          │               │
          │ model         │
          │ parameters    │
          │ secure input  │
          │ inference     │
          └───────┬───────┘
                  │
                  ▼
            prediction
  ```
  Core security claim:
  > Sensitive model parameters and/or security-critical inference operations are
  > protected from the Normal World by executing them inside an OP-TEE Trusted
  > Application.
  This is academically stronger than simply saying "TinyML runs on Raspberry Pi."
  ---
  ### Phase 8 — Add model protection
  Investigate a protected path:
  ```text
  Normal World
       │
       │ encrypted input
       ▼
   OP-TEE TA
       │
       ├── decrypt
       ├── inference
       ├── confidence
       └── result protection
       │
       ▼
   Normal World
  ```
  Potential protected assets:
  - model parameters
  - sensitive input features
  - intermediate values
  - inference result
  This strengthens the **Trusted AI / confidential AI** angle.
  ---
  ### Phase 9 — Measure everything
  Measurement is essential for PhD/research value.
  Compare:
  | Experiment      | Normal World |    OP-TEE |
  | --------------- | -----------: | --------: |
  | Model size      |      measure |   measure |
  | Memory          |      measure |   measure |
  | Inference time  |      measure |   measure |
  | CPU utilization |      measure |   measure |
  | Energy          |      measure |   measure |
  | Accuracy        |      measure |   measure |
  | Security        |     baseline | protected |
  Produce graphs such as:
  ```text
  Inference latency
          │
          │             ███
          │             ███
          │       ███   ███
          │  ███  ███   ███
          └────────────────────
            REE   TEE   QAI
  ```
  and metrics for:
  - model size
  - memory consumption
  - inference latency
  - energy per inference
  - accuracy
  These measurements turn the implementation into an **experimental research
  project**.
  ---
  ### Phase 10 — Final architecture
  Eventual QAI-OPTEE prototype:
  ```text
                   Raspberry Pi 5
  ┌──────────────────────────────────────────────┐
  │                                              │
  │              NORMAL WORLD                    │
  │                                              │
  │  Sensor / IoT application                    │
  │          │                                   │
  │          ▼                                   │
  │  Feature extraction                          │
  │          │                                   │
  │          ▼                                   │
  │       OP-TEE Client                          │
  │          │                                   │
  │          │  TEEC_InvokeCommand               │
  │          ▼                                   │
  ├──────────────────────────────────────────────┤
  │                    TEE                       │
  │                                              │
  │          ┌──────────────────────┐            │
  │          │       QAI TA         │            │
  │          │                      │            │
  │          │ Secure model         │            │
  │          │ Quantum parameters   │            │
  │          │ Secure inference     │            │
  │          │ Integrity checking   │            │
  │          └──────────┬───────────┘            │
  │                     │                        │
  ├─────────────────────┼────────────────────────┤
  │                     ▼                        │
  │             Secure Prediction                │
  │                                              │
  └──────────────────────────────────────────────┘
  ```
  ---
  ## Immediate next step
  Do **not** jump to full QAI yet. Follow this sequence:
  ```text
  [✓] Raspberry Pi 5
  [✓] OP-TEE built
  [✓] OP-TEE deployed
  [✓] Secure World running
  [✓] xtest working
  [✓] Basic TA communication
          │
          ▼
  [1] Create clean qai_ta
          │
          ▼
  [2] Implement C inference
          │
          ▼
  [3] REE → QAI TA → REE
          │
          ▼
  [4] Measure inference latency
          │
          ▼
  [5] Train tiny model on Mac
          │
          ▼
  [6] Deploy model parameters to TA
          │
          ▼
  [7] Secure TinyML inference
          │
          ▼
  [8] Quantum/hybrid model on Mac
          │
          ▼
  [9] Compact QAI inference in TA
          │
          ▼
  [10] Security + performance evaluation
  ```
  ---
  ## First concrete milestone
  Build **`qai_ta` on the physical RPi5 OP-TEE environment** with:
  ```text
  Input:       [10, 20, -5, 3]
                   ↓
               QAI Client
                   ↓
               OP-TEE
                   ↓
                QAI TA
                   ↓
          C inference function
                   ↓
  Prediction:     1
  Confidence:    28
  Execution:     xxx µs
  ```
  Once that works on the **physical Raspberry Pi 5**, replace the simple C
  function with a **trained TinyML model**, then introduce the
  **quantum/hybrid component**.
