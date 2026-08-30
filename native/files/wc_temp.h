#ifndef WAIFUCAD_WC_TEMP_H
#define WAIFUCAD_WC_TEMP_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Create and reserve a temporary file securely.  directory may be NULL or an
 * empty string to use the host's normal temporary directory.  On success the
 * file exists, is closed, and its NUL-terminated path is written to output.
 * The caller owns removal of the path.
 */
int wc_make_temp_file(const char *directory, char *output, size_t capacity);

#ifdef __cplusplus
}
#endif

#endif
