# Raspberry Pi 5 OP-TEE documentation

Paths in these manuals are relative to the **`pi5-optee` repository root**.
This repo is independent (and may be used as a submodule elsewhere); it does
**not** require a parent `~/optee` directory.

## Platform (OP-TEE on Pi 5)

Directory: [`platform/`](platform/)

- LaTeX source: [`platform/rpi5-optee-manual.tex`](platform/rpi5-optee-manual.tex)
- PDF: [`platform/rpi5-optee-manual.pdf`](platform/rpi5-optee-manual.pdf)
- Build `xtest` on device: [`platform/build-xtest-on-rpi5.md`](platform/build-xtest-on-rpi5.md)

## QAI-OPTEE prototype

Directory: [`qai/`](qai/)

- **Running manual (start here):** [`qai/qai-optee-running-manual.md`](qai/qai-optee-running-manual.md)
- Roadmap: [`qai/qai-optee-prototype-roadmap.md`](qai/qai-optee-prototype-roadmap.md)
- Architecture: [`qai/qai-optee-architecture.md`](qai/qai-optee-architecture.md)
- Source: [`../optee_examples/qai_ta/`](../optee_examples/qai_ta/)

## HAI quantum-hybrid SVM, secure world

Directory: [`hai-qhsvm/`](hai-qhsvm/)

- Secure-world estimate: [`hai-qhsvm/hai-qhsvm-pi5-tee-resource-estimate-arXiv_2409.04935.md`](hai-qhsvm/hai-qhsvm-pi5-tee-resource-estimate-arXiv_2409.04935.md)
- Secure-world analysis: [`hai-qhsvm/hai-qhsvm-pi5-tee-resource-analysis-arXiv_2409.04935.md`](hai-qhsvm/hai-qhsvm-pi5-tee-resource-analysis-arXiv_2409.04935.md)
- HAI 20.07 scored in the TA, compared with Tables I and II: [`hai-qhsvm/hai-qhsvm-pi5-tee-hai-tables-arXiv_2409.04935.md`](hai-qhsvm/hai-qhsvm-pi5-tee-hai-tables-arXiv_2409.04935.md)
- TinyML HAI inference in the TA: [`hai-qhsvm/hai-qhsvm-pi5-tee-tinyml-output.md`](hai-qhsvm/hai-qhsvm-pi5-tee-tinyml-output.md)
- TinyML, QOC-SVM, and QMOC-SVM, 8-qubit and 16-qubit, on the same draw: [`hai-qhsvm/hai-qhsvm-pi5-tee-tinyml-vs-qai.md`](hai-qhsvm/hai-qhsvm-pi5-tee-tinyml-vs-qai.md)
- QMOC-SVM on the same draw: [`hai-qhsvm/hai-qhsvm-pi5-tee-qmoc-svm.md`](hai-qhsvm/hai-qhsvm-pi5-tee-qmoc-svm.md)
- Machine-readable measurements: [`experimental-data/`](experimental-data/) (`manifest.csv` lists every file)
- Paper: [`hai-qhsvm/2409.04935v1.pdf`](hai-qhsvm/2409.04935v1.pdf)

## Build PDF (platform manual)

```bash
cd docs/platform
# If the tectonic binary is present:
../.bin/tectonic rpi5-optee-manual.tex

# Or with system TeX Live:
pdflatex rpi5-optee-manual.tex
pdflatex rpi5-optee-manual.tex
```

Contents: architecture, failure/retry log, scripts, validation, user manual
(figures + tables).
