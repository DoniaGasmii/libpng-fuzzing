#include <png.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <setjmp.h>

typedef struct {
    uint8_t *data;
    size_t size;
    size_t offset;
} mem_buf;

static const uint8_t PNG_SIG[8] = {0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'};

void read_fn(png_structp png_ptr, png_bytep out, png_size_t len) {
    mem_buf *buf = (mem_buf *)png_get_io_ptr(png_ptr);
    if (!buf) { png_error(png_ptr, "read error"); return; }

    while (len > 0) {
        if (buf->offset < 8) {
            /* serve synthetic PNG signature for the first 8 virtual bytes */
            size_t take = len < (8 - buf->offset) ? len : (8 - buf->offset);
            memcpy(out, PNG_SIG + buf->offset, take);
            buf->offset += take;
            out += take;
            len -= take;
        } else {
            /* serve actual fuzz data, shifted back by the 8 synthetic bytes */
            size_t idx = buf->offset - 8;
            if (idx >= buf->size) { png_error(png_ptr, "read error"); return; }
            size_t take = len < (buf->size - idx) ? len : (buf->size - idx);
            memcpy(out, buf->data + idx, take);
            buf->offset += take;
            out += take;
            len -= take;
        }
    }
}

/* --- push API callbacks ---------------------------------------------------
   Called by libpng as it processes data fed through png_process_data.
   info_cb fires once headers are parsed, row_cb fires per decoded row,
   end_cb fires when IEND is reached.                                     */
static void push_info_cb(png_structp png_ptr, png_infop info_ptr) {
    png_set_expand(png_ptr);
    png_set_scale_16(png_ptr);
    png_set_gray_to_rgb(png_ptr);
    png_set_alpha_mode(png_ptr, PNG_ALPHA_PNG, PNG_DEFAULT_sRGB);
    png_set_gamma(png_ptr, PNG_DEFAULT_sRGB, PNG_DEFAULT_sRGB);
    png_read_update_info(png_ptr, info_ptr);
}

static void push_row_cb(png_structp png_ptr, png_bytep new_row,
                        png_uint_32 row_num, int pass) {
    (void)png_ptr; (void)new_row; (void)row_num; (void)pass;
}

static void push_end_cb(png_structp png_ptr, png_infop info_ptr) {
    (void)png_ptr; (void)info_ptr;
}
/* ------------------------------------------------------------------------- */

int main(int argc, char **argv) {
    FILE *fp = stdin;
    uint8_t *data = NULL;
    size_t size = 0;

    if (argc > 1) {
        fp = fopen(argv[1], "rb");
        if (!fp) return 0;
    }

    fseek(fp, 0, SEEK_END);
    long fsize = ftell(fp);
    rewind(fp);

    if (fsize <= 0) {
        if (argc > 1) fclose(fp);
        return 0;
    }

    size = (size_t)fsize;
    data = malloc(size);
    if (!data) {
        if (argc > 1) fclose(fp);
        return 0;
    }

    if (fread(data, 1, size, fp) != size) {
        free(data);
        if (argc > 1) fclose(fp);
        return 0;
    }

    if (argc > 1) fclose(fp);

    if (size == 0) {
        free(data);
        return 0;
    }

    /* ======================================================================
       PATH 1: pull API  (pngread.c)
       Synchronous pull-based parsing — your code drives libpng.
       ====================================================================== */
    do {
        png_structp png_ptr = png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
        if (!png_ptr) break;

        png_infop info_ptr = png_create_info_struct(png_ptr);
        if (!info_ptr) { png_destroy_read_struct(&png_ptr, NULL, NULL); break; }

        png_infop end_info = NULL;

        if (setjmp(png_jmpbuf(png_ptr))) {
            png_destroy_read_struct(&png_ptr, &info_ptr, &end_info);
            break;
        }

        mem_buf buf = { data, size, 0 };
        png_set_read_fn(png_ptr, &buf, read_fn);

        /* unknown chunk handler: libpng calls this for every chunk type it
           does not recognise, exercising the unknown-chunk processing code */
        png_set_keep_unknown_chunks(png_ptr, PNG_HANDLE_CHUNK_ALWAYS, NULL, 0);

        png_read_info(png_ptr, info_ptr);

        png_uint_32 width, height;
        int bit_depth, color_type;
        png_get_IHDR(png_ptr, info_ptr, &width, &height,
                     &bit_depth, &color_type, NULL, NULL, NULL);

        png_set_expand(png_ptr);
        png_set_scale_16(png_ptr);
        png_set_gray_to_rgb(png_ptr);
        png_set_alpha_mode(png_ptr, PNG_ALPHA_PNG, PNG_DEFAULT_sRGB);
        png_color_16 background = {0, 128, 128, 128, 128};
        png_set_background(png_ptr, &background, PNG_BACKGROUND_GAMMA_SCREEN, 0, 1.0);
        png_set_gamma(png_ptr, PNG_DEFAULT_sRGB, PNG_DEFAULT_sRGB);
        png_read_update_info(png_ptr, info_ptr);

        png_size_t rowbytes = png_get_rowbytes(png_ptr, info_ptr);

        if (height == 0 || height > 5000 ||
            rowbytes == 0 || rowbytes > 10000000) {
            png_destroy_read_struct(&png_ptr, &info_ptr, &end_info);
            break;
        }

        png_bytep *rows = malloc(sizeof(png_bytep) * height);
        if (!rows) { png_destroy_read_struct(&png_ptr, &info_ptr, &end_info); break; }

        for (png_uint_32 i = 0; i < height; i++) {
            rows[i] = malloc(rowbytes);
            if (!rows[i]) {
                for (png_uint_32 j = 0; j < i; j++) free(rows[j]);
                free(rows);
                png_destroy_read_struct(&png_ptr, &info_ptr, &end_info);
                break;
            }
        }

        png_read_image(png_ptr, rows);

        for (png_uint_32 i = 0; i < height; i++) free(rows[i]);
        free(rows);

        end_info = png_create_info_struct(png_ptr);
        png_read_end(png_ptr, end_info);

        png_destroy_read_struct(&png_ptr, &info_ptr, &end_info);
    } while (0);

    /* ======================================================================
       PATH 2: push/progressive API  (pngpread.c)
       libpng drives a separate internal state machine — you feed it data.
       Covers streaming parser code paths the pull API never reaches.
       ====================================================================== */
    do {
        png_structp push_ptr = png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
        if (!push_ptr) break;

        png_infop push_info = png_create_info_struct(push_ptr);
        if (!push_info) { png_destroy_read_struct(&push_ptr, NULL, NULL); break; }

        if (!setjmp(png_jmpbuf(push_ptr))) {
            png_set_progressive_read_fn(push_ptr, NULL,
                                        push_info_cb, push_row_cb, push_end_cb);
            /* signature fed separately so fuzz data starts at byte 0 */
            png_process_data(push_ptr, push_info, (png_bytep)PNG_SIG, 8);
            png_process_data(push_ptr, push_info, data, size);
        }

        png_destroy_read_struct(&push_ptr, &push_info, NULL);
    } while (0);

    free(data);
    return 0;
}
