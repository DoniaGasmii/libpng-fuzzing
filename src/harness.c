
#include <stdio.h>
#include <stdlib.h>
#include <png.h>
#include <setjmp.h>

int main(int argc, char **argv) {
    if (argc < 2) return 0;

    FILE *fp = fopen(argv[1], "rb");
    if (!fp) return 0;

    png_structp png = png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
    if (!png) {
        fclose(fp);
        return 0;
    }

    png_infop info = png_create_info_struct(png);
    if (!info) {
        png_destroy_read_struct(&png, NULL, NULL);
        fclose(fp);
        return 0;
    }

    // 🔴 CRITICAL: catch libpng errors
    if (setjmp(png_jmpbuf(png))) {
        png_destroy_read_struct(&png, &info, NULL);
        fclose(fp);
        return 0;
    }

    png_init_io(png, fp);

    png_read_info(png, info);

    // Enable transformations → more coverage
    png_set_expand(png);
    png_set_strip_16(png);
    png_set_gray_to_rgb(png);

    png_read_update_info(png, info);

    int height = png_get_image_height(png, info);
    int rowbytes = png_get_rowbytes(png, info);

    // Allocate image buffer
    png_bytep *rows = malloc(sizeof(png_bytep) * height);
    for (int y = 0; y < height; y++) {
        rows[y] = malloc(rowbytes);
    }

    png_read_image(png, rows);

    // Cleanup
    for (int y = 0; y < height; y++) {
        free(rows[y]);
    }
    free(rows);

    png_destroy_read_struct(&png, &info, NULL);
    fclose(fp);

    return 0;
}