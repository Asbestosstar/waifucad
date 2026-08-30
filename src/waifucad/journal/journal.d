module waifucad.journal.journal;

import core.stdc.stdio : FILE, fopen, fclose, fprintf, fflush;

struct Journal
{
    FILE* stream;
    bool recording;
    uint sequence;

    bool start(const(char)* path) nothrow @nogc
    {
        stop();
        stream = fopen(path, "wb".ptr);
        if (stream is null)
            return false;
        recording = true;
        sequence = 0;
        fprintf(stream, "# WaifuCAD semantic journal v2\n");
        fprintf(stream, "# language=scl\n");
        fprintf(stream, "# replay=waifucad-batch --journal-in <file>\n");
        fflush(stream);
        return true;
    }

    void stop() nothrow @nogc
    {
        if (stream !is null)
        {
            fflush(stream);
            fclose(stream);
        }
        stream = null;
        recording = false;
    }

    void record(const(char)* command) nothrow @nogc
    {
        if (!recording || stream is null || command is null)
            return;
        ++sequence;
        fprintf(stream, "%s\n", command);
        fflush(stream);
    }
}



