# Scripts

`Scripts` are user- or AI-authored executable CAD programs. SCL is the built-in language. `.wcs` means Ruby-like SCL source; the historical whitespace command form is retained as `.scl` for compatibility/migration. Later Ruby, Java, Groovy and Crystal runtime adapters use the journal back-end ABI and remain separate from the Ruby-like SCL surface.

The root `make_todos.sh` utility is not a CAD Script. It is a developer utility that concatenates the relevant repository text into `todos.txt` so an AI coding agent can read the current architecture and TODO state before preparing a patch.



AI inspection should use the shared read-only getter catalogue rather than receiving raw model pointers. Ruby-like `.wcs` can write `kind = get_feature_kind(:body)`; legacy `.scl` uses `get_feature_kind kind body`. See `config/scl_getters.json` and `docs/AI_MODEL_INSPECTION.md`.

