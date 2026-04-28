FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/opt/aflpp:${PATH}"

#  Install system dependencies FIRST (critical!)
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    wget \
    curl \
    python3 \
    python3-pip \
    gdb \
    vim \
    # LLVM/Clang for afl-clang-fast (required for instrumentation)
    llvm \
    clang \
    lld \
    # QEMU user-mode for black-box fuzzing
    qemu-user \
    # libpng build dependencies
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

#  Build AFL++ (simpler target, avoids gcc_plugin issues)
RUN git clone --depth 1 https://github.com/AFLplusplus/AFLplusplus.git /opt/aflpp && \
    cd /opt/aflpp && \
    # Use 'source-only' to skip problematic gcc_plugin build
    make source-only -j$(nproc) && \
    make install -j$(nproc)

#  Verify installation
RUN afl-cc --version && afl-fuzz --help | head -5

WORKDIR /work

# Copy your project files
COPY . .

CMD ["/bin/bash"]