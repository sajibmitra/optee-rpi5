# Raspberry Pi 5 OP-TEE documentation

Paths in these manuals are relative to the **`pi5-optee` repository root**.
This repo is independent (and may be used as a submodule elsewhere); it does
**not** require a parent `~/optee` directory.

## Platform (OP-TEE on Pi 5)

- LaTeX source: `rpi5-optee-manual.tex`
- PDF: `rpi5-optee-manual.pdf` (≤ 10 pages)
- Build `xtest` on device: `build-xtest-on-rpi5.md`

## HAI quantum-hybrid SVM on Pi 5

- Resource estimate (RAM, CPU time, rail power): [`hai-qhsvm-pi5-resource-estimate-arXiv_2409.04935.md`](hai-qhsvm-pi5-resource-estimate-arXiv_2409.04935.md)
- Procedure and hardware requirements (training vs CPU inference): [`hai-qhsvm-pi5-resource-analysis-arXiv_2409.04935.md`](hai-qhsvm-pi5-resource-analysis-arXiv_2409.04935.md)
- Secure-world estimate: [`hai-qhsvm-pi5-tee-resource-estimate-arXiv_2409.04935.md`](hai-qhsvm-pi5-tee-resource-estimate-arXiv_2409.04935.md)
- Secure-world analysis: [`hai-qhsvm-pi5-tee-resource-analysis-arXiv_2409.04935.md`](hai-qhsvm-pi5-tee-resource-analysis-arXiv_2409.04935.md)
- HAI 20.07 scored in the TA, compared with Tables I and II: [`hai-qhsvm-pi5-tee-hai-tables-arXiv_2409.04935.md`](hai-qhsvm-pi5-tee-hai-tables-arXiv_2409.04935.md)
- Paper: [`2409.04935v1.pdf`](2409.04935v1.pdf)

## QAI-OPTEE prototype

- **Running manual (start here):** [`qai-optee-running-manual.md`](qai-optee-running-manual.md)
- Roadmap: [`qai-optee-prototype-roadmap.md`](qai-optee-prototype-roadmap.md)
- Architecture: [`qai-optee-architecture.md`](qai-optee-architecture.md)
- Source: [`../optee_examples/qai_ta/`](../optee_examples/qai_ta/)

## Build PDF (platform manual)

```bash
cd docs
# If tectonic binary is present:
./.bin/tectonic rpi5-optee-manual.tex

# Or with system TeX Live:
pdflatex rpi5-optee-manual.tex
pdflatex rpi5-optee-manual.tex
```

Contents: architecture, failure/retry log, scripts, validation, user manual
(figures + tables).
