#include "CZlib.h"
#include <limits.h>
#include <stdlib.h>
#include <zlib.h>

static int transform(const uint8_t *input, size_t input_size, uint8_t **output, size_t *output_size, int inflate_mode) {
    if (input == NULL || output == NULL || output_size == NULL || input_size > UINT_MAX) return Z_STREAM_ERROR;
    z_stream stream = {0};
    stream.next_in = (Bytef *)input;
    stream.avail_in = (uInt)input_size;
    int result = inflate_mode ? inflateInit2(&stream, -MAX_WBITS) : deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY);
    if (result != Z_OK) return result;
    size_t capacity = input_size > 1024 ? input_size * 2 : 1024;
    uint8_t *buffer = malloc(capacity);
    if (buffer == NULL) { if (inflate_mode) inflateEnd(&stream); else deflateEnd(&stream); return Z_MEM_ERROR; }
    do {
        if (stream.total_out == capacity) {
            if (capacity > SIZE_MAX / 2) { free(buffer); if (inflate_mode) inflateEnd(&stream); else deflateEnd(&stream); return Z_MEM_ERROR; }
            capacity *= 2;
            uint8_t *expanded = realloc(buffer, capacity);
            if (expanded == NULL) { free(buffer); if (inflate_mode) inflateEnd(&stream); else deflateEnd(&stream); return Z_MEM_ERROR; }
            buffer = expanded;
        }
        stream.next_out = buffer + stream.total_out;
        stream.avail_out = (uInt)(capacity - stream.total_out);
        result = inflate_mode ? inflate(&stream, Z_NO_FLUSH) : deflate(&stream, Z_FINISH);
    } while ((inflate_mode && result == Z_OK) || (!inflate_mode && result == Z_OK));
    int expected = inflate_mode ? Z_STREAM_END : Z_STREAM_END;
    if (result != expected) { free(buffer); if (inflate_mode) inflateEnd(&stream); else deflateEnd(&stream); return result; }
    *output = buffer;
    *output_size = stream.total_out;
    if (inflate_mode) inflateEnd(&stream); else deflateEnd(&stream);
    return Z_OK;
}

int dicomkit_inflate_raw(const uint8_t *input, size_t input_size, uint8_t **output, size_t *output_size) { return transform(input, input_size, output, output_size, 1); }
int dicomkit_deflate_raw(const uint8_t *input, size_t input_size, uint8_t **output, size_t *output_size) { return transform(input, input_size, output, output_size, 0); }
void dicomkit_zlib_free(void *pointer) { free(pointer); }
