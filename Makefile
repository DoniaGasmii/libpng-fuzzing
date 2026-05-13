# =============================================================
# CS-412 Fuzzing Lab — libpng 1.2.52
# =============================================================

LIBPNG_VERSION  := 1.2.52
LIBPNG_DIR      := /opt/libpng-$(LIBPNG_VERSION)

SRC_DIR         := src
FINDINGS_DIR    := findings
FINDINGS_QEMU   := findings-qemu
FINDINGS_NOASAN := findings-no-asan
FINDINGS_PERS   := findings-persistent

CC_AFL          := afl-clang-fast
CC_VANILLA      := gcc

CFLAGS_ASAN     := -g -O1 -fsanitize=address
LDFLAGS_ASAN    := -fsanitize=address
CFLAGS_NOASAN   := -g -O1
SEEDS           := interesting_seeds

.PHONY: all build fuzz fuzz-no-asan fuzz-persistent fuzz-qemu \
        plot plot-qemu clean

# -------------------------------------------------------------
# Default target
# -------------------------------------------------------------
all: build

# -------------------------------------------------------------
# 1. Patch libpng (remove CRC checks for effective fuzzing)
# -------------------------------------------------------------
patch-libpng:
	cd $(LIBPNG_DIR) && \
	patch --forward -p0 \
	  < /opt/aflpp/utils/libpng_no_checksum/libpng-nocrc.patch || true

# -------------------------------------------------------------
# 2. Build instrumented library (ASan + AFL++ instrumentation)
# -------------------------------------------------------------
build-lib-asan: patch-libpng
	cd $(LIBPNG_DIR) && \
	CC=$(CC_AFL) CFLAGS="$(CFLAGS_ASAN)" LDFLAGS="$(LDFLAGS_ASAN)" \
	./configure --disable-shared \
	            --prefix=$(shell pwd)/install_instrumented \
	            --host=x86_64-linux-gnu && \
	make -j$(nproc) && make install

# -------------------------------------------------------------
# 3. Build vanilla library (no instrumentation, no sanitizers)
# -------------------------------------------------------------
build-lib-vanilla: patch-libpng
	cd $(LIBPNG_DIR) && \
	make distclean || true && \
	CC=$(CC_VANILLA) CFLAGS="$(CFLAGS_NOASAN)" \
	./configure --disable-shared \
	            --prefix=$(shell pwd)/install_vanilla \
	            --host=x86_64-linux-gnu && \
	make -j$(nproc) && make install

# -------------------------------------------------------------
# 4. Build harnesses
# -------------------------------------------------------------
build: build-lib-asan
	$(CC_AFL) $(SRC_DIR)/harness.c \
		-I./install_instrumented/include \
		-L./install_instrumented/lib \
		-lpng12 -lz -lm \
		$(CFLAGS_ASAN) $(LDFLAGS_ASAN) \
		-o png_harness
	@echo "✅ Instrumented harness built: png_harness"

build-persistent: build-lib-asan
	$(CC_AFL) $(SRC_DIR)/harness_persistent.c \
		-I./install_instrumented/include \
		-L./install_instrumented/lib \
		-lpng12 -lz -lm \
		$(CFLAGS_ASAN) $(LDFLAGS_ASAN) \
		-o png_harness_persistent
	@echo "✅ Persistent harness built: png_harness_persistent"

build-vanilla: build-lib-vanilla
	$(CC_VANILLA) $(SRC_DIR)/harness.c \
		-I./install_vanilla/include \
		-L./install_vanilla/lib \
		-lpng12 -lz -lm \
		$(CFLAGS_NOASAN) \
		-o png_harness_qemu
	@echo "✅ Vanilla harness built: png_harness_qemu"

build-lib-no-asan: patch-libpng
	cd $(LIBPNG_DIR) && \
	make distclean || true && \
	CC=$(CC_AFL) CFLAGS="$(CFLAGS_NOASAN)" \
	./configure --disable-shared \
	            --prefix=$(shell pwd)/install_no_asan \
	            --host=x86_64-linux-gnu && \
	make -j$(nproc) && make install

build-no-asan: build-lib-no-asan
	$(CC_AFL) $(SRC_DIR)/harness.c \
		-I./install_no_asan/include \
		-L./install_no_asan/lib \
		-lpng12 -lz -lm \
		$(CFLAGS_NOASAN) \
		-o png_harness_no_asan
	@echo "✅ No-ASan harness built: png_harness_no_asan"

# -------------------------------------------------------------
# 5. Fuzzing campaigns
# -------------------------------------------------------------

# Run 1 — main campaign: ASan + fork mode (white-box)
fuzz: build
	mkdir -p $(FINDINGS_DIR)
	AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1 \
	AFL_SKIP_CPUFREQ=1 \
	afl-fuzz -i $(SEEDS) -o $(FINDINGS_DIR) -x png.dict \
	         -- ./png_harness

# Run 2 — no sanitizer + fork mode (Q8 speed comparison)
fuzz-no-asan: build-no-asan
	mkdir -p $(FINDINGS_NOASAN)
	AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1 \
	AFL_SKIP_CPUFREQ=1 \
	afl-fuzz -i $(SEEDS) -o $(FINDINGS_NOASAN) -x png.dict \
	         -- ./png_harness_no_asan

# Run 3 — ASan + persistent mode (Q8 speed comparison)
fuzz-persistent: build-persistent
	mkdir -p $(FINDINGS_PERS)
	AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1 \
	AFL_SKIP_CPUFREQ=1 \
	afl-fuzz -i $(SEEDS) -o $(FINDINGS_PERS) -x png.dict \
	         -- ./png_harness_persistent

# Run 4 — O0 optimization flag test (Q2 justification)
build-O0: patch-libpng
	cd $(LIBPNG_DIR) && \
	CC=$(CC_AFL) CFLAGS="-g -O0 -fsanitize=address" LDFLAGS="$(LDFLAGS_ASAN)" \
	./configure --disable-shared \
	            --prefix=$(shell pwd)/install_O0 \
	            --host=x86_64-linux-gnu && \
	make -j$(nproc) && make install
	$(CC_AFL) $(SRC_DIR)/harness.c \
		-I./install_O0/include \
		-L./install_O0/lib \
		-lpng12 -lz -lm \
		-g -O0 -fsanitize=address $(LDFLAGS_ASAN) \
		-o png_harness_O0
	@echo "✅ O0 harness built: png_harness_O0"

fuzz-O0: build-O0
	mkdir -p findings-O0
	AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1 \
	AFL_SKIP_CPUFREQ=1 \
	afl-fuzz -i $(SEEDS) -o findings-O0 -x png.dict \
	         -- ./png_harness_O0

# Run 6 — LTO instrumentation (Q2/Q8 comparison)
build-lto: patch-libpng
	cd $(LIBPNG_DIR) && \
	CC=afl-clang-lto CFLAGS="$(CFLAGS_ASAN)" LDFLAGS="$(LDFLAGS_ASAN)" \
	./configure --disable-shared \
	            --prefix=$(shell pwd)/install_lto \
	            --host=x86_64-linux-gnu && \
	make -j$(nproc) && make install
	afl-clang-lto $(SRC_DIR)/harness.c \
		-I./install_lto/include \
		-L./install_lto/lib \
		-lpng12 -lz -lm \
		$(CFLAGS_ASAN) $(LDFLAGS_ASAN) \
		-o png_harness_lto
	@echo "✅ LTO harness built: png_harness_lto"

fuzz-lto: build-lto
	mkdir -p findings-lto
	AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1 \
	AFL_SKIP_CPUFREQ=1 \
	afl-fuzz -i $(SEEDS) -o findings-lto -x png.dict \
	         -- ./png_harness_lto

plot-lto:
	afl-plot findings-lto/default/ plot_output_lto/

# Run 5 — QEMU mode / black-box (Q7)
fuzz-qemu: build-vanilla
	mkdir -p $(FINDINGS_QEMU)
	AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1 \
	AFL_SKIP_CPUFREQ=1 \
	afl-fuzz -Q -i $(SEEDS) -o $(FINDINGS_QEMU) -x png.dict \
	         -- ./png_harness_qemu @@

# -------------------------------------------------------------
# 6. Generate afl-plot output
# -------------------------------------------------------------
plot:
	afl-plot $(FINDINGS_DIR)/default/ plot_output/

plot-qemu:
	afl-plot $(FINDINGS_QEMU)/default/ plot_output_qemu/

plot-no-asan:
	afl-plot $(FINDINGS_NOASAN)/default/ plot_output_no_asan/

plot-persistent:
	afl-plot $(FINDINGS_PERS)/default/ plot_output_persistent/

# -------------------------------------------------------------
# 7. Clean
# -------------------------------------------------------------
clean:
	rm -rf $(FINDINGS_DIR) $(FINDINGS_QEMU) \
	       $(FINDINGS_NOASAN) $(FINDINGS_PERS) findings-O0 findings-lto \
	       png_harness png_harness_persistent \
	       png_harness_qemu png_harness_no_asan png_harness_O0 png_harness_lto \
	       install_instrumented install_vanilla install_O0 install_lto install_no_asan \
	       plot_output/ plot_output_qemu/ \
	       plot_output_no_asan/ plot_output_persistent/ plot_output_lto/