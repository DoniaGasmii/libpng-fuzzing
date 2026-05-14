# CS-412 Software Security — Fuzzing Lab
## Fuzzing libpng with AFL++
**Team:** Donia Gasmi, Louis Gogniat, Khaled Kerouch, Srushti Singh  
**Course:** CS-412 Software Security, EPFL Spring 2026  
**Target:** libpng 1.2.52

---

## Overview
This repository contains our fuzzing campaign against `libpng 1.2.52`
using AFL++ with compile-time instrumentation and AddressSanitizer.
We discovered a unique crash caused by a `stack-use-after-scope`
bug in `png_inflate()` (`pngrutil.c`). The bug was fixed in libpng 1.2.53.

---

## Repository Structure
```
main/
├── Dockerfile                        # Complete fuzzing environment
├── Makefile                          # All build and fuzz targets
├── png.dict                          # Extended PNG dictionary
├── src/
│   ├── harness_SuaS_v2.c             # Fork-mode fuzzing harness
│   └── persistent_harness_SuaS_v2.c  # Persistent-mode fuzzing harness
├── interesting_seeds/                # Seed corpus
└── outputs/                          # Campaign results and plots
```

---

## Requirements
- Docker Desktop (Windows/Mac) or Docker Engine (Linux)
---

## Quick Start

### 1. Build the Docker image
```bash
docker build -t fuzz-lab .
```

### 2. Start the container
```bash
docker run --rm -it -v "$PWD":/work fuzz-lab
```

---

## Fuzzing Targets

| Target | Description | Command |
|--------|-------------|---------|
| Main campaign | ASan + fork mode | `make new_fuzz` |
| Persistent mode | ASan + persistent mode (faster) | `make optifuzz` |
| No sanitizer | Fork mode, no ASan | `make fuzz-no-asan` |
| QEMU mode | Binary-only, black-box | `make fuzz-qemu` |
---

## Reproducing the Crash

After running `make new_fuzz`, crashes are saved in `minimized_findings/default/crashes/`.

```bash
ASAN_OPTIONS=symbolize=1 ./png_harness \
  "minimized_findings/default/crashes/id:000000,..."
```

Expected output: `AddressSanitizer: stack-use-after-scope` in `png_inflate()`.
