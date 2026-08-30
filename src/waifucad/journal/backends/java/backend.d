module waifucad.journal.backends.java.backend;

import waifucad.journal.backend_api : JournalBackendV1, WC_JOURNAL_BACKEND_ABI_V1;

JournalBackendV1 javaBackendStub() nothrow @nogc
{
    JournalBackendV1 backend;
    backend.abiVersion = WC_JOURNAL_BACKEND_ABI_V1;
    backend.name = "java".ptr;
    backend.extension = ".java".ptr;
    return backend;
}



