module waifucad.journal.backends.ruby.backend;

import waifucad.journal.backend_api : JournalBackendV1, WC_JOURNAL_BACKEND_ABI_V1;

JournalBackendV1 rubyBackendStub() nothrow @nogc
{
    JournalBackendV1 backend;
    backend.abiVersion = WC_JOURNAL_BACKEND_ABI_V1;
    backend.name = "ruby".ptr;
    backend.extension = ".rb".ptr;
    return backend;
}



