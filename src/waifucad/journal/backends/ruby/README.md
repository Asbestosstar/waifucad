# Ruby journal back-end

Reserved adapter directory.  Implement the host runtime behind `JournalBackendV1` using a C ABI bridge.  The adapter should translate model mutations into the same transaction/SCL command layer so recording and replay semantics remain consistent.


Ruby-style SCL surface syntax is separate from this adapter. The SCL normaliser only provides Ruby-shaped CAD syntax inside the deterministic BetterC interpreter; this directory remains reserved for a future bridge to an actual Ruby runtime through the journal C ABI.


