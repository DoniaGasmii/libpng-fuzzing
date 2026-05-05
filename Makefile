# Configuration
LIBPNG_VERSION := 1.2.52
LIBPNG_URL := https://download.sourceforge.net/libpng/libpng-$(LIBPNG_VERSION).tar.gz
LIBPNG_DIR := /opt/libpng-$(LIBPNG_VERSION)

# Directories
SRC_DIR := src
SEEDS_DIR := seeds
FINDINGS_DIR := findings
FINDINGS_QEMU_DIR := findings-qemu

# Compiler Flags
CC_INSTRUMENTED := afl-clang-fast
CC_VANILLA := gcc
CFLAGS := -g -O1 -fsanitize=address
LDFLAGS := -fsanitize=address

.PHONY: all build fuzz fuzz-qemu clean download-libpng patch-libpng

all: build

# 1. Download libpng if not present
# $(LIBPNG_DIR):
# 	wget $(LIBPNG_URL)
# 	tar xf libpng-$(LIBPNG_VERSION).tar.gz

# 2. Apply CRC Patch (Critical for effective fuzzing!)
patch-libpng: $(LIBPNG_DIR)
	cd $(LIBPNG_DIR) && patch --forward -p0 < /opt/aflpp/utils/libpng_no_checksum/libpng-nocrc.patch || true
# 3. Build Instrumented Library (White-Box)
build-instrumented-lib: patch-libpng
	cd $(LIBPNG_DIR) && \
	CC=$(CC_INSTRUMENTED) CFLAGS="$(CFLAGS)" LDFLAGS="$(LDFLAGS)" \
	./configure --disable-shared --prefix=$(shell pwd)/install_instrumented --host=x86_64-linux-gnu && \
	make -j$(nproc) && make install

# 4. Build Harness (Instrumented)
build-harness-instrumented: build-instrumented-lib
	$(CC_INSTRUMENTED) $(SRC_DIR)/harness_SuaS.c \
		-I./install_instrumented/include \
		-L./install_instrumented/lib \
		-lpng12 -lz -lm \
		$(CFLAGS) $(LDFLAGS) \
		-o png_harness

# 5. Main Build Target (Compiles Lib + Harness)
build: build-harness-instrumented
	@echo "✅ Build complete. Run 'make fuzz' to start."

# 6. Run Fuzzing Campaign (White-Box)
fuzz: build
	mkdir -p findings
	export AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1; \
	export AFL_SKIP_CPUFREQ=1; \
	afl-fuzz -i final_seeds -o findings -x png.dict -- ./png_harness

optifuzz: build 
	mkdir -p $(FINDINGS_DIR) 
	export AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1; \ 
	export AFL_SKIP_CPUFREQ=1; \ 
	export AFL_FAST_CAL=1; \
	export AFL_DISABLE_TRIM=0; \ 
	afl-fuzz -i final_seeds/ -o opti_findings -x png.dict -t 100 -- ./png_harness

# --- BLACK-BOX / QEMU MODE TARGETS ---

# 7. Build Vanilla Library (No Instrumentation, No Sanitizers)
build-vanilla-lib: $(LIBPNG_DIR)
	# Ensure patch is applied here too so comparison is fair regarding CRC
	cd $(LIBPNG_DIR) && patch -p0 < /opt/aflpp/utils/libpng_no_checksum/libpng-nocrc.patch || true
	cd $(LIBPNG_DIR) && \
	CC=$(CC_VANILLA) CFLAGS="-g -O1" \
	./configure --disable-shared --prefix=$(shell pwd)/install_vanilla && \
	make -j$(nproc) && make install

# 8. Build Harness (Vanilla)
build-harness-vanilla: build-vanilla-lib
	$(CC_VANILLA) $(SRC_DIR)/harness_CVE-2016-10087.c \
		-I./install_vanilla/include \
		-L./install_vanilla/lib \
		-lpng12 -lz -lm \
		-g -O1 \
		-o png_harness_qemu

# 9. Run QEMU Fuzzing Campaign (Black-Box)
fuzz-qemu: build-harness-vanilla
	mkdir -p $(FINDINGS_QEMU_DIR)
	AFL_SKIP_CPUFREQ=1 afl-fuzz -Q -i $(SEEDS_DIR) -o $(FINDINGS_QEMU_DIR) -x png.dict -- ./png_harness_qemu @@

# 10. Clean up artifacts (but keep downloaded libpng to save time)
clean:
	rm -rf $(FINDINGS_DIR) $(FINDINGS_QEMU_DIR) png_harness png_harness_qemu install_instrumented install_vanilla
	rm -rf $(LIBPNG_DIR)/.libs $(LIBPNG_DIR)/.deps
# 	@echo "Cleaned findings and binaries."