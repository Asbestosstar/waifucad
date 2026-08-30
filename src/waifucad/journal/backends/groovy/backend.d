module waifucad.journal.backends.groovy.backend;

import waifucad.journal.backend_api : JournalBackendV1, WC_JOURNAL_BACKEND_ABI_V1;

JournalBackendV1 groovyBackendStub() nothrow @nogc
{
    JournalBackendV1 backend;
    backend.abiVersion = WC_JOURNAL_BACKEND_ABI_V1;
    backend.name = "groovy".ptr;
    backend.extension = ".groovy".ptr;
    return backend;
}



