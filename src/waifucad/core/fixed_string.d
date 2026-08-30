module waifucad.core.fixed_string;

import core.stdc.string : strlen, memcpy, strcmp;

// Fixed strings keep the bootstrap kernel deterministic and allocation-free.
private void setFixedString(char* destination, size_t capacity, size_t* used, const(char)* value) nothrow @nogc
{
    if (destination is null || used is null || capacity == 0)
        return;
    *used = 0;
    destination[0] = 0;
    if (value is null)
        return;

    auto sourceLength = strlen(value);
    auto copyLength = sourceLength < capacity - 1 ? sourceLength : capacity - 1;
    if (copyLength != 0)
        memcpy(destination, value, copyLength);
    destination[copyLength] = 0;
    *used = copyLength;
}

struct FixedString64
{
    char[64] storage;
    size_t length;

    void clear() nothrow @nogc
    {
        length = 0;
        storage[0] = 0;
    }

    void set(const(char)* value) nothrow @nogc
    {
        setFixedString(storage.ptr, storage.length, &length, value);
    }

    const(char)* ptr() const nothrow @nogc
    {
        return storage.ptr;
    }

    bool equals(const(char)* other) const nothrow @nogc
    {
        return other !is null && strcmp(storage.ptr, other) == 0;
    }
}

struct FixedString256
{
    char[256] storage;
    size_t length;

    void clear() nothrow @nogc
    {
        length = 0;
        storage[0] = 0;
    }

    void set(const(char)* value) nothrow @nogc
    {
        setFixedString(storage.ptr, storage.length, &length, value);
    }

    const(char)* ptr() const nothrow @nogc
    {
        return storage.ptr;
    }

    bool equals(const(char)* other) const nothrow @nogc
    {
        return other !is null && strcmp(storage.ptr, other) == 0;
    }
}



