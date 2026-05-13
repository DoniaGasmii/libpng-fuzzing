# CS-412 Software Security — Fuzzing Lab
## Fuzzing libpng with AFL++

**Team:** Donia Gasmi, Louis Gogniat, Khaled Kerrouche, Srushti Singh
**Course:** CS-412 Software Security, EPFL Spring 2026
**Target:** libpng 1.2.52

---

## Overview

This repository contains our fuzzing campaign against `libpng 1.2.52`
using AFL++ with compile-time instrumentation and AddressSanitizer.
We discovered 13 unique crashes caused by a `stack-use-after-scope`
bug in `png_inflate()` (`pngrutil.c`), reachable via both `iCCP` and
`zTXt` chunk handlers. The bug is fixed in libpng 1.2.53.

---

## Repository Structure

```
submission/
├── Dockerfile              # Complete fuzzing environment
├── Makefile                # All build and fuzz targets
├── png.dict                # Extended PNG dictionary
├── src/
│   ├── harness.c           # Fork-mode fuzzing harness
│   └── harness_persistent.c# Persistent-mode fuzzing harness
├── interesting_seeds/      # 12 diverse PNG seed files
├── outputs/
│   ├── run1_main_campaign/ # Instrumented campaign results (1h)
│   └── run2_qemu/          # QEMU-mode campaign results (1h + 17h)
└── report.pdf              # Final report
```

---

## Requirements

- Docker Desktop (Windows/Mac) or Docker Engine (Linux)
- ~4 GB disk space (for AFL++ build and libpng compilation)
- ~2 GB RAM

---

## Quick Start

### 1. Build the Docker image

```bash
docker build -t fuzz-lab .
```

This installs all dependencies, builds AFL++ with QEMU support,
and downloads libpng 1.2.52.

### 2. Start the container

```bash
docker run --rm -it -v "$PWD":/work fuzz-lab
```

### 3. Run the main instrumented campaign (white-box)

```bash
make fuzz
```

Runs AFL++ with ASan instrumentation against `interesting_seeds/`
for as long as desired. Results go to `findings/default/`.

### 4. Generate plots

```bash
make plot
```

Output goes to `plot_output/`.

---

## All Fuzzing Targets

| Target | Description | Command |
|--------|-------------|---------|
| Main campaign | ASan + fork mode | `make fuzz` |
| Persistent mode | ASan + persistent mode (faster) | `make fuzz-persistent` |
| No sanitizer | Fork mode, no ASan (Q8 comparison) | `make fuzz-no-asan` |
| QEMU mode | Binary-only, black-box (Q7) | `make fuzz-qemu` |
| O0 flag test | Optimization comparison (Q2) | `make fuzz-O0` |
| LTO mode | afl-clang-lto comparison (Q2) | `make fuzz-lto` |

---

## Reproducing the Crash

The crashing input is saved in `outputs/run1_main_campaign/findings/default/crashes/`.
To reproduce with ASan symbolization:

```bash
# Inside the container, after make build
ASAN_OPTIONS=symbolize=1 ./png_harness \
  "outputs/run1_main_campaign/findings/default/crashes/id:000000,sig:06,..."
```

Expected output: `AddressSanitizer: stack-use-after-scope` in `png_inflate()`.

---

## Notes

- The CRC patch is applied automatically during `make build`.
- QEMU mode requires the image built with the provided Dockerfile
  (includes QEMU build dependencies and `meson` via pip).
- All campaigns use `interesting_seeds/` as the seed corpus.
- Findings and plots from our campaigns are in `outputs/`.
