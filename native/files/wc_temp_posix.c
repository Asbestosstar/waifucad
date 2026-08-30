#define _POSIX_C_SOURCE 200809L

#include "wc_temp.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef WC_TEMP_DEFAULT_DIRECTORY
#define WC_TEMP_DEFAULT_DIRECTORY "/tmp"
#endif

static const char *wc_select_temp_directory(const char *requested)
{
    const char *environment;

    if (requested != NULL && requested[0] != '\0')
        return requested;

    environment = getenv("TMPDIR");
    if (environment != NULL && environment[0] != '\0')
        return environment;

    return WC_TEMP_DEFAULT_DIRECTORY;
}

int wc_make_temp_file(const char *directory, char *output, size_t capacity)
{
    const char *selected;
    size_t length;
    int written;
    int descriptor;

    if (output == NULL || capacity == 0)
        return EINVAL;

    output[0] = '\0';
    selected = wc_select_temp_directory(directory);
    length = strlen(selected);
    if (length == 0)
        return EINVAL;

    written = snprintf(output, capacity, "%s%swaifucad-off-XXXXXX",
                       selected,
                       selected[length - 1] == '/' ? "" : "/");
    if (written < 0 || (size_t)written >= capacity) {
        output[0] = '\0';
        return ENAMETOOLONG;
    }

    descriptor = mkstemp(output);
    if (descriptor < 0) {
        int error = errno != 0 ? errno : EIO;
        output[0] = '\0';
        return error;
    }

    if (close(descriptor) != 0) {
        int error = errno != 0 ? errno : EIO;
        unlink(output);
        output[0] = '\0';
        return error;
    }

    return 0;
}
