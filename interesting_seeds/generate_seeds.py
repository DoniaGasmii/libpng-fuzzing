import struct
import zlib

def chunk(type_str, data):
    t = type_str.encode()
    crc = zlib.crc32(t + data) & 0xffffffff
    return struct.pack('>I', len(data)) + t + data + struct.pack('>I', crc)

# 1x1 RGB image reused across all seeds
SIG  = b'\x89PNG\r\n\x1a\n'
IHDR = chunk('IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0))
IDAT = chunk('IDAT', zlib.compress(b'\x00\xff\x00\x00'))  # filter + R G B
IEND = chunk('IEND', b'')

# --- seed 1: gAMA chunk ---------------------------------------------------
# gAMA stores gamma * 100000 as a uint32.
# 45455 = 1/2.2 * 100000 (standard sRGB approximation).
# Triggers the file-gamma code path inside libpng instead of the fallback.
gama = chunk('gAMA', struct.pack('>I', 45455))
with open('seed_gama.png', 'wb') as f:
    f.write(SIG + IHDR + gama + IDAT + IEND)

# --- seed 2: unknown chunk ------------------------------------------------
# PNG chunk type naming rules:
#   byte 0 lowercase = ancillary (safe to ignore if unknown)
#   byte 1 lowercase = private
#   byte 2 must be uppercase (reserved)
#   byte 3 lowercase = safe to copy
# 'fuZz' satisfies all rules — libpng does not know this type and will
# call the unknown chunk handler registered by png_set_keep_unknown_chunks.
unknown = chunk('fuZz', b'unknown chunk payload for fuzzing')
with open('seed_unknown.png', 'wb') as f:
    f.write(SIG + IHDR + unknown + IDAT + IEND)

# --- seed 3: zTXt after IDAT ----------------------------------------------
# zTXt = zlib-compressed text chunk.
# Placed AFTER IDAT so it is only parsed by png_read_end, not png_read_info.
# Format: keyword + \x00 + compression_method(1 byte) + compressed_text
text = b'fuzzing libpng zTXt chunk parser'
ztxt = chunk('zTXt', b'Comment\x00\x00' + zlib.compress(text))
with open('seed_ztxt.png', 'wb') as f:
    f.write(SIG + IHDR + IDAT + ztxt + IEND)

# --- seed 4: iTXt after IDAT ----------------------------------------------
# iTXt = international UTF-8 text chunk.
# Format: keyword + \x00 + compression_flag + compression_method
#         + language_tag + \x00 + translated_keyword + \x00 + text
itxt_payload = (
    b'Description\x00'   # keyword + null
    b'\x00'              # compression flag (0 = not compressed)
    b'\x00'              # compression method
    b'en\x00'            # language tag + null
    b'\x00'              # translated keyword (empty) + null
    + 'libpng iTXt fuzzing seed'.encode('utf-8')
)
itxt = chunk('iTXt', itxt_payload)
with open('seed_itxt.png', 'wb') as f:
    f.write(SIG + IHDR + IDAT + itxt + IEND)

print("generated: seed_gama.png, seed_unknown.png, seed_ztxt.png, seed_itxt.png")
