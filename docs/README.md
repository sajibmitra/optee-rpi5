# Raspberry Pi 5 OP-TEE documentation

## Platform (OP-TEE on Pi 5)

- LaTeX source: `rpi5-optee-manual.tex`
- PDF: `rpi5-optee-manual.pdf` (≤ 10 pages)
- Build `xtest` on device: `build-xtest-on-rpi5.md`

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
