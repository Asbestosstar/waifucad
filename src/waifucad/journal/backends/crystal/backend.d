module waifucad.journal.backends.crystal.backend;

import waifucad.journal.backend_api : JournalBackendV1, WC_JOURNAL_BACKEND_ABI_V1;

JournalBackendV1 crystalBackendStub() nothrow @nogc
{
    JournalBackendV1 backend;
    backend.abiVersion = WC_JOURNAL_BACKEND_ABI_V1;
    backend.name = "crystal".ptr;
    backend.extension = ".cr".ptr;
    return backend;
}



