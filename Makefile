G_DIR):
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

min_fuzz: build 
	mkdir -p $(FINDINGS_DIR) 
	export AFL_I_DONT_CARE_ABOUT_MISSING_
