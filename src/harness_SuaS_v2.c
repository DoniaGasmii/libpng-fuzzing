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

    png_structp png_ptr = png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
    if (!png_ptr) {
        free(data);
        return 0;
    }

    png_infop info_ptr = png_create_info_struct(png_ptr);
    if (!info_ptr) {
        png_destroy_read_struct(&png_ptr, NULL, NULL);
        free(data);
        return 0;
    }

    /* declared before setjmp so the error handler can destroy it even if
       png_read_end has not been reached yet */
    png_infop end_info = NULL;

    if (setjmp(png_jmpbuf(png_ptr))) {
        png_destroy_read_struct(&png_ptr, &info_ptr, &end_info);
        free(data);
        return 0;
    }

    mem_buf buf = { data, size, 0 };
    png_set_read_fn(png_ptr, &buf, read_fn);

    png_read_info(png_ptr, info_ptr);

    png_uint_32 width, height;
    int bit_depth, color_type;
    png_get_IHDR(png_ptr, info_ptr, &width, &height,
                 &bit_depth, &color_type, NULL, NULL, NULL);

    /* --- transforms -------------------------------------------------------
       These expand the decoder pipeline: palette->RGB, <8-bit->8-bit,
       tRNS->alpha, 16-bit->8-bit scaling, grayscale->RGB, alpha handling.
       png_read_update_info must be called after setting transforms so that
       png_get_rowbytes returns the post-transform row size.              */
    png_set_expand(png_ptr);
    png_set_scale_16(png_ptr);
    png_set_gray_to_rgb(png_ptr);
    png_set_alpha_mode(png_ptr, PNG_ALPHA_PNG, PNG_DEFAULT_sRGB);
    png_read_update_info(png_ptr, info_ptr);
    /* --------------------------------------------------------------------- */

    png_size_t rowbytes = png_get_rowbytes(png_ptr, info_ptr);

    if (height == 0 || height > 5000 ||
        rowbytes == 0 || rowbytes > 10000000) {
        png_destroy_read_struct(&png_ptr, &info_ptr, &end_info);
        free(data);
        return 0;
    }

    png_bytep *rows = malloc(sizeof(png_bytep) * height);
    if (!rows) {
        png_destroy_read_struct(&png_ptr, &info_ptr, &end_info);
        free(data);
        return 0;
    }

    for (png_uint_32 i = 0; i < height; i++) {
        rows[i] = malloc(rowbytes);
        if (!rows[i]) {
            for (png_uint_32 j = 0; j < i; j++) free(rows[j]);
            free(rows);
            png_destroy_read_struct(&png_ptr, &info_ptr, &end_info);
            free(data);
            return 0;
        }
    }

    png_read_image(png_ptr, rows);

    for (png_uint_32 i = 0; i < height; i++) free(rows[i]);
    free(rows);

    /* --- trailing chunks --------------------------------------------------
       png_read_end processes any chunks after IDAT: tEXt, zTXt, iTXt,
       tIME, etc. These have historically had parser bugs and are never
       reached without this call.                                          */
    end_info = png_create_info_struct(png_ptr);
    png_read_end(png_ptr, end_info);
    /* --------------------------------------------------------------------- */

    /* --- metadata accessors -----------------------------------------------
       Explicitly touch every chunk accessor so the fuzzer can reach the
       per-chunk parsing and validation code inside libpng.               */
    png_textp text_ptr;
    int num_text = 0;
    png_get_text(png_ptr, info_ptr, &text_ptr, &num_text);
    if (end_info)
        png_get_text(png_ptr, end_info, &text_ptr, &num_text);

    png_uint_32 res_x = 0, res_y = 0;
    int unit_type = 0;
    png_get_pHYs(png_ptr, info_ptr, &res_x, &res_y, &unit_type);

    png_timep mod_time = NULL;
    png_get_tIME(png_ptr, info_ptr, &mod_time);

    png_color_16p bkg = NULL;
    png_get_bKGD(png_ptr, info_ptr, &bkg);

    double gamma_val = 0.0;
    png_get_gAMA(png_ptr, info_ptr, &gamma_val);
    /* --------------------------------------------------------------------- */

    png_destroy_read_struct(&png_ptr, &info_ptr, &end_info);
    free(data);

    return 0;
}
