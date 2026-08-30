#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "wc_temp.h"

int main(void)
{
    char first[512];
    char second[512];
    struct stat info;

    if (wc_make_temp_file(NULL, first, sizeof first) != 0)
        return 10;
    if (wc_make_temp_file(NULL, second, sizeof second) != 0) {
        unlink(first);
        return 11;
    }
    if (strcmp(first, second) == 0) {
        unlink(first);
        unlink(second);
        return 12;
    }
    if (stat(first, &info) != 0 || stat(second, &info) != 0) {
        unlink(first);
        unlink(second);
        return 13;
    }
    if (unlink(first) != 0 || unlink(second) != 0)
        return 14;

    puts("secure temporary-file service passed");
    return 0;
}
