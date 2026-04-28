RUN wget https://download.sourceforge.net/libpng/libpng-1.2.56.tar.gz && \
    tar xf libpng-1.2.56.tar.gz && \
    cd libpng-1.2.56 && \
    patch -p0 </work/patches/libpng-nocrc.patch && \
    CC=afl-clang-fast CFLAGS="-fsanitize=address -g -O1" \
    ./configure --disable-shared --prefix=/opt/libpng && \
    make -j$(nproc) && make install
