FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/opt/aflpp:${PATH}"
ENV LIBPNG_VERSION=1.2.52
ENV LIBPNG_DIR=/opt/libpng-${LIBPNG_VERSION}

#  Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    wget \
    curl \
    python3 \
    python3-pip \
    gdb \
    vim \
    llvm \
    clang \
    lld \
    qemu-user \
    zlib1g-dev \
    gnuplot \
    libglib2.0-dev \
    libpixman-1-dev \
    ninja-build \
    && rm -rf /var/lib/apt/lists/*

# Install meson via pip (apt version too old for QEMU build)
RUN pip3 install meson

#  Build AFL++ with QEMU support
RUN git clone --depth 1 https://github.com/AFLplusplus/AFLplusplus.git /opt/aflpp && \
    cd /opt/aflpp && \
    make source-only -j$(nproc) && \
    make install -j$(nproc) && \
    cd qemu_mode && ./build_qemu_support.sh

#  Build libpng from source
RUN cd /opt && \
    wget https://download.sourceforge.net/libpng/libpng-${LIBPNG_VERSION}.tar.gz && \
    tar xf libpng-${LIBPNG_VERSION}.tar.gz && \
    rm libpng-${LIBPNG_VERSION}.tar.gz

#  Verify installation
RUN afl-cc --version && afl-fuzz --help | head -5

WORKDIR /work
COPY . .
CMD ["/bin/bash"]