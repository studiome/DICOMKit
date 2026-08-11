#include "TurboJPEGShim.h"

#include <turbojpeg/turbojpeg.h>

static int decode(const uint8_t *source, size_t source_size,
                  uint8_t *destination, size_t destination_size,
                  int width, int height, int pixel_format, size_t components) {
    if (source == NULL || destination == NULL || source_size == 0 || width <= 0 || height <= 0 ||
        destination_size != (size_t)width * (size_t)height * components) {
        return -1;
    }

    tjhandle decoder = tj3Init(TJINIT_DECOMPRESS);
    if (decoder == NULL) {
        return -1;
    }

    const int valid_header = tj3DecompressHeader(decoder, source, source_size) == 0 &&
        tj3Get(decoder, TJPARAM_JPEGWIDTH) == width &&
        tj3Get(decoder, TJPARAM_JPEGHEIGHT) == height &&
        tj3Get(decoder, TJPARAM_PRECISION) == 8;
    const int result = valid_header &&
        tj3Decompress8(decoder, source, source_size, destination, 0, pixel_format) == 0 ? 0 : -1;
    tj3Destroy(decoder);
    return result;
}

int dicomkit_turbojpeg_decode_rgb8(const uint8_t *source, size_t source_size,
                                   uint8_t *destination, size_t destination_size,
                                   int width, int height) {
    return decode(source, source_size, destination, destination_size, width, height, TJPF_RGB, 3);
}

int dicomkit_turbojpeg_decode_gray8(const uint8_t *source, size_t source_size,
                                    uint8_t *destination, size_t destination_size,
                                    int width, int height) {
    return decode(source, source_size, destination, destination_size, width, height, TJPF_GRAY, 1);
}

static int validate_lossless_header(tjhandle decoder, const uint8_t *source,
                                    size_t source_size, int width, int height,
                                    int samples_per_pixel, int *precision,
                                    int *selection_value) {
    if (tj3DecompressHeader(decoder, source, source_size) != 0 ||
        tj3Get(decoder, TJPARAM_JPEGWIDTH) != width ||
        tj3Get(decoder, TJPARAM_JPEGHEIGHT) != height ||
        tj3Get(decoder, TJPARAM_LOSSLESS) != 1) {
        return -1;
    }
    const int decoded_precision = tj3Get(decoder, TJPARAM_PRECISION);
    if (decoded_precision < 2 || decoded_precision > 16) {
        return -1;
    }
    const int decoded_selection_value = tj3Get(decoder, TJPARAM_LOSSLESSPSV);
    if (decoded_selection_value < 1 || decoded_selection_value > 7) {
        return -1;
    }
    *precision = decoded_precision;
    *selection_value = decoded_selection_value;
    return samples_per_pixel == 1 || samples_per_pixel == 3 ? 0 : -1;
}

int dicomkit_turbojpeg_decode_lossless8(const uint8_t *source, size_t source_size,
                                        uint8_t *destination, size_t destination_size,
                                        int width, int height, int samples_per_pixel,
                                        int *precision, int *selection_value) {
    if (source == NULL || destination == NULL || precision == NULL || selection_value == NULL || source_size == 0 ||
        width <= 0 || height <= 0 ||
        destination_size != (size_t)width * (size_t)height * (size_t)samples_per_pixel) {
        return -1;
    }
    tjhandle decoder = tj3Init(TJINIT_DECOMPRESS);
    if (decoder == NULL || validate_lossless_header(decoder, source, source_size, width, height,
                                                    samples_per_pixel, precision, selection_value) != 0 ||
        *precision > 8) {
        tj3Destroy(decoder);
        return -1;
    }
    const int pixel_format = samples_per_pixel == 1 ? TJPF_GRAY : TJPF_RGB;
    const int result = tj3Decompress8(decoder, source, source_size, destination, 0, pixel_format) == 0 ? 0 : -1;
    tj3Destroy(decoder);
    return result;
}

int dicomkit_turbojpeg_decode_lossless16(const uint8_t *source, size_t source_size,
                                         uint16_t *destination, size_t destination_count,
                                         int width, int height, int samples_per_pixel,
                                         int *precision, int *selection_value) {
    if (source == NULL || destination == NULL || precision == NULL || selection_value == NULL || source_size == 0 ||
        width <= 0 || height <= 0 ||
        destination_count != (size_t)width * (size_t)height * (size_t)samples_per_pixel) {
        return -1;
    }
    tjhandle decoder = tj3Init(TJINIT_DECOMPRESS);
    if (decoder == NULL || validate_lossless_header(decoder, source, source_size, width, height,
                                                    samples_per_pixel, precision, selection_value) != 0 ||
        *precision <= 8) {
        tj3Destroy(decoder);
        return -1;
    }
    const int pixel_format = samples_per_pixel == 1 ? TJPF_GRAY : TJPF_RGB;
    const int result = *precision <= 12 ?
        (tj3Decompress12(decoder, source, source_size, (short *)destination, 0, pixel_format) == 0 ? 0 : -1) :
        (tj3Decompress16(decoder, source, source_size, destination, 0, pixel_format) == 0 ? 0 : -1);
    tj3Destroy(decoder);
    return result;
}
