module waifucad.platform.temp_files;

extern(C) int wc_make_temp_file(const(char)* directory, char* output, size_t capacity) nothrow @nogc;

int makeSecureTemporaryFile(const(char)* directory, char* output, size_t capacity) nothrow @nogc
{
    if (output is null || capacity == 0)
        return 1;
    return wc_make_temp_file(directory, output, capacity);
}
