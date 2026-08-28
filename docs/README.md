# Raspberry Pi 5 OP-TEE documentation

LaTeX source: `rpi5-optee-manual.tex`  
PDF: `rpi5-optee-manual.pdf` (≤ 10 pages)

## Build PDF

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
