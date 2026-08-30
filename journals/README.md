# Journals

WaifuCAD journals are semantic SCL command streams rather than recordings of mouse movement or widget co-ordinates. A recorded journal can therefore be inspected, edited as text and replayed in batch mode.

```sh
./bin/waifucad-batch --script examples/scripts/multicore_features.wcs --journal-out journals/demo.wjournal
./bin/waifucad-batch --journal-in journals/demo.wjournal --dump-model
```

Journal comment lines begin with `#`. The current v2 header identifies SCL and gives the replay entry point. Future versions will add build/kernel/Mod metadata and verification hashes without changing the modelling commands themselves.
