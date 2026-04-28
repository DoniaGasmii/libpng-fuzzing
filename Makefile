LIBPNG_URL = https://download.sourceforge.net/libpng/libpng-1.2.56.tar.gz
libpng-1.2.56.tar.gz:
	wget $(LIBPNG_URL)

libpng-1.2.56/: libpng-1.2.56.tar.gz
	tar xf libpng-1.2.56.tar.gz
	cd libpng-1.2.56 && patch -p0 < ../patches/libpng-nocrc.patch
