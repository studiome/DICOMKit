#include <stddef.h>
#include <stdint.h>

int dicomkit_inflate_raw(const uint8_t *input, size_t input_size, uint8_t **output, size_t *output_size);
int dicomkit_deflate_raw(const uint8_t *input, size_t input_size, uint8_t **output, size_t *output_size);
void dicomkit_zlib_free(void *pointer);
