# libpng-fuzzing
Set up and execute a coverage-guided fuzzing campaign using AFL++ against a real-world open-source library.

##  Host Terminal (WSL)
Run these **outside** the container:
```bash
# 1. Get group's latest code
git pull origin main

# 2. Build the Docker image, if needed (runs Dockerfile)
docker build -t fuzz-lab .

# 3. Start container & mount your project folder
docker run --rm -it -v "$PWD":/work fuzz-lab
```
---

## Inside Container (`/work#`)
```bash
# 4. Clean previous builds & compile everything
make clean && make build

# 5. Launch instrumented fuzzing campaign
make fuzz
make fuzz-qemu
```
> Let it run ≥12 secs lol. Press `Ctrl+C` to stop. Files in `findings/` stay on host thanks to `-v`.

---

```bash
# Generate graphs after campaign
afl-plot findings/default/ plot_output/
afl-plot findings-qemu/default/ plot_output_qemu/

# Crash triage
afl-tmin -i findings/default/crashes/<id> -o poc_min.png -- ./png_harness @@
ASAN_OPTIONS=symbolize=1 ./png_harness poc_min.png
```
