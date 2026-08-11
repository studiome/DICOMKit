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
