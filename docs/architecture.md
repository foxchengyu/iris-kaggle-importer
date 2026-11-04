# Import flow

1. `IrisKaggle.API_ImportSimple(slug)` calls `IrisKaggle.Importer.Import`.
2. `IrisKaggle.Credentials.Resolve` reads `KAGGLE_USERNAME` / `KAGGLE_KEY`, then
   falls back to the values stored in `^IrisKaggle`.
3. `IrisKaggle.Client.Download` calls
   `GET /api/v1/datasets/download/{owner}/{name}` with HTTP basic auth and
   streams the zip to a per process temporary directory.
4. `IrisKaggle.Archive.Extract` unzips with Python's `zipfile` (standard library
   only), skipping entries that would escape the target directory.
5. `IrisKaggle.Importer.PickFile` uses the requested file name, or the largest
   `.csv` in the archive.
6. `IrisKaggle.Csv` reads the header and up to 200 sample rows with a streaming
   RFC 4180 parser that follows quoted newlines.
7. `IrisKaggle.Schema.Build` classifies each column as bool / int / float /
   date / string and sizes VARCHAR columns from the sample.
8. `IrisKaggle.Importer.CreateTable` drops the previous table with the same name
   and creates the new one.
9. Rows are streamed in batches of 250 and written with multi-row `INSERT`s. A
   failing batch is retried row by row.
10. `IrisKaggle.Manifest` stores one audit row per import.

# Transport

All HTTP goes through `IrisKaggle.Client`, which builds every request in one
place:

* **TLS.** `IrisKaggle.TLS.Ensure` returns a client SSL configuration, creating
  `IrisKaggleTLS` when the installation has none. Without it, HTTPS fails with
  error `#6159` on images that ship no SSL configuration.
* **Proxy.** When `KAGGLE_PROXY` is set, requests are sent through an HTTP
  `CONNECT` tunnel. `%Net.HttpRequest` needs both `ProxyTunnel` and `ProxyHTTPS`
  for an HTTPS target; setting only `ProxyTunnel` fails during the handshake.
* **Redirects.** The download endpoint answers with a redirect to a signed
  storage URL, so `FollowRedirect` is enabled and gzip is disabled for the
  binary response.

# Why Embedded Python is used only for unzipping

IRIS has no built-in zip reader, and writing an inflate implementation in
ObjectScript would be a lot of untested code. Python's `zipfile` is part of the
standard library that ships with IRIS Embedded Python, so no package
installation is needed and the container stays stock.
