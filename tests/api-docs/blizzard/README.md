# Vendored Blizzard API Documentation

This directory holds Blizzard's public API documentation tables (the
`Blizzard_APIDocumentationGenerated/*.lua` files that ship with the WoW
client). They are vendored here so the taint analyzer can run without a
WoW install.

## Source

The canonical source is the `live` branch of
[`Gethe/wow-ui-source`](https://github.com/Gethe/wow-ui-source):
`Interface/AddOns/Blizzard_APIDocumentationGenerated/`

Online mirror: https://www.townlong-yak.com/framexml/live/Blizzard_APIDocumentation

## Current state

This directory contains the `12.1.0.69382` snapshot of Blizzard's generated API
documentation tables. The taint analyzer reads these files through the derived
index at `tests/api-docs/api-index.lua`, so the corpus and index must stay in
sync. After replacing or adding Blizzard documentation files, regenerate the
derived index:

```sh
lua tools/test_taint.lua --update-index
```

## Refresh procedure

When WoW patches, file contents may change. To refresh:

1. Clone the upstream `live` branch and copy its
   `Interface/AddOns/Blizzard_APIDocumentationGenerated/*.lua` files into this
   directory. Replace existing files; do not merge.
2. Run `lua tools/test_taint.lua --update-index` to regenerate
   `tests/api-docs/api-index.lua`.
3. Inspect the diff in `api-index.lua`. New entries are normal; removed
   entries may indicate functions that have been deprecated.
4. Run `lua tools/test_taint.lua --self-test` to verify nothing broke.
5. Commit corpus + api-index.lua together with a message noting the patch
   version.

## Patch coverage

The vendored corpus snapshots the API doc as of a specific patch. The derived
`api-index.lua` is committed alongside; CI verifies they stay in sync via a
regenerate-and-diff check.

## License

Blizzard's API documentation tables ship as part of FrameXML and are public.
Vendoring them here is standard practice in the WoW addon ecosystem.
