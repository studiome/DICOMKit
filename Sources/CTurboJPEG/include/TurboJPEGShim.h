#ifndef TurboJPEGShim_h
#define TurboJPEGShim_h

#include <stddef.h>
#include <stdint.h>

int dicomkit_turbojpeg_decode_rgb8(const uint8_t *source, size_t source_size,
                                   uint8_t *destination, size_t destination_size,
                                   int width, int height);
int dicomkit_turbojpeg_decode_gray8(const uint8_t *source, size_t source_size,
                                    uint8_t *destination, size_t destination_size,
                                    int width, int height);
int dicomkit_turbojpeg_decode_lossless8(const uint8_t *source, size_t source_size,
                                        uint8_t *destination, size_t destination_size,
                                        int width, int height, int samples_per_pixel,
                                        int *precision, int *selection_value);
int dicomkit_turbojpeg_decode_lossless16(const uint8_t *source, size_t source_size,
                                         uint16_t *destination, size_t destination_count,
                                         int width, int height, int samples_per_pixel,
                                         int *precision, int *selection_value);

#endif
