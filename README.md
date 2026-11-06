# iris-kaggle-importer &nbsp; [![中文版](https://img.shields.io/badge/README-中文版-red)](README.zh.md)

Load a [Kaggle](https://www.kaggle.com/datasets) dataset into InterSystems IRIS
as a real SQL table — with **one SQL statement**.

```sql
SELECT IrisKaggle.API_ImportSimple('uciml/iris');
```

```text
{"status":"ok","dataset":"uciml/iris","file":"Iris.csv","table":"KG_uciml_iris_Iris",
 "rowsImported":150,"columns":6,"failedRows":0,"bytesDownloaded":4258,"elapsedSeconds":3}
```

The importer authenticates with the Kaggle API, downloads the dataset archive,
extracts it, picks a CSV, infers the column types, creates the table and streams
the rows in. Everything runs inside IRIS: no pip packages, no sidecar service.

---

## Prerequisites

- **Docker** (for the containerised setup) or an existing **InterSystems IRIS 2023.1+** instance.
- **[Kaggle API credentials](https://www.kaggle.com/settings)** — required to download
  datasets from kaggle.com. Without credentials you can still import local CSV
  files via `ImportFile`, and the demo falls back to a bundled sample CSV.

  Get your credentials on kaggle.com: **Settings → API → Create New Token**.
  This downloads a `kaggle.json` file with your `username` and `key`.

## Why

Kaggle is where most public tabular data lives, but moving a dataset into IRIS
usually means a throw-away download script, manual unzipping, and hand written
DDL. This project makes it a single call that works from SQL, ObjectScript or a
terminal, and keeps an audit trail of what was loaded.

## Quick start

### 1. Get a Kaggle API key

On kaggle.com: **your avatar → Settings → API → Create New Token**. This
downloads `kaggle.json`:

```json
{"username":"your_user","key":"0123456789abcdef0123456789abcdef"}
```

### 2. Start IRIS

```bash
git clone https://github.com/foxchengyu/iris-kaggle-importer.git
cd iris-kaggle-importer
KAGGLE_USERNAME=your_user KAGGLE_KEY=0123456789abcdef docker compose up -d --build
```

IRIS starts on <http://localhost:52773/csp/sys/UtilHome.csp> (`_SYSTEM` / `SYS`).

Run the demo import (works without credentials using a bundled sample CSV):

```bash
docker compose exec iris iris session IRIS < docker/demo.script
```

With Kaggle credentials, point the demo at a live dataset:

```sql
SELECT IrisKaggle.API_ImportSimple('uciml/iris')
```

### Existing IRIS instance

1. Import `src/cls` with **Management Portal → System Explorer → Classes →
   Import**, or from a terminal:

   ```objectscript
   Do $SYSTEM.OBJ.LoadDir("<repo>/src/cls", "ck")
   ```

2. Store credentials once (or use the environment variables):

   ```objectscript
   Do ##class(IrisKaggle.CLI).Setup("your_user", "0123456789abcdef")
   ```

## Usage

### From SQL

```sql
-- one line: download and import the largest CSV
SELECT IrisKaggle.API_ImportSimple('uciml/iris');

-- full control: dataset, target table, file, max rows, dataset version
SELECT IrisKaggle.API_ImportDataset('uciml/iris', 'SQLUser.Iris', 'Iris.csv', 1000, 0);

-- import a CSV that is already on the IRIS server
SELECT IrisKaggle.API_ImportFile('/data/train.csv', 'SQLUser.Train', 0);

-- credentials without environment variables
SELECT IrisKaggle.API_SetCredentials('your_user', '0123456789abcdef');

-- what has been imported so far
SELECT IrisKaggle.API_ListImports();
```

### From ObjectScript

```objectscript
Do ##class(IrisKaggle.CLI).Setup("your_user", "0123456789abcdef")
Do ##class(IrisKaggle.CLI).Demo()                             ; uciml/iris
Do ##class(IrisKaggle.CLI).Import("uciml/iris")               ; everything
Do ##class(IrisKaggle.CLI).Import("uciml/iris", "SQLUser.Iris", "Iris.csv", 500)
Do ##class(IrisKaggle.CLI).ImportFile("/data/train.csv", "SQLUser.Train")
```

### Querying the result

```sql
SELECT TOP 5 * FROM KG_uciml_iris_Iris
```

The result is a normal table, so indices, joins, BI tools, Embedded Python and
Interoperability productions all work as usual.

## Options

| Argument | Meaning | Default |
| --- | --- | --- |
| `dataset` | Dataset slug, `owner/name` | required |
| `targetTable` | Target table, optionally `Schema.Table` | derived from dataset + file |
| `fileName` | CSV inside the archive (exact or suffix match) | largest CSV |
| `maxRows` | Row limit, `0` = all | `0` |
| `version` | Dataset version number, `0` = latest | `0` |

The default table name is `KG_<owner>_<name>_<file stem>`, sanitised to a valid
IRIS identifier.

### Proxies and restricted networks

Outbound HTTPS must reach `www.kaggle.com` and the storage host that serves the
archive. Behind a corporate proxy, set `KAGGLE_PROXY`; the client opens an HTTP
`CONNECT` tunnel and negotiates TLS through it:

```bash
KAGGLE_PROXY=http://proxy.example.com:8080 docker compose up -d --build
```

In ObjectScript, set the `Proxy` property on `IrisKaggle.Client` instead.

### TLS configuration

IRIS needs a client SSL configuration for every HTTPS call. Some images ship
without one, which makes requests fail with error `#6159`. The importer looks
for a configuration and creates `IrisKaggleTLS` on first use when none exists.
To use a different one, set the `SSLConfiguration` property on
`IrisKaggle.Client`. Nothing is created when a configuration with that name
already exists.

## How it works

```
SQL / ObjectScript
        │
        ▼
 IrisKaggle.Importer ──► IrisKaggle.Client ──► https://www.kaggle.com/api/v1
        │                     basic auth, /datasets/download/{owner}/{name}
        ▼
 IrisKaggle.Archive ──► unzip with the Python standard library (zipfile)
        │
        ▼
 IrisKaggle.Csv ──► streaming RFC 4180 reader (quotes, escaped quotes, newlines)
        │
        ▼
 IrisKaggle.Schema ──► int / float / bool / date / string inference
        │
        ▼
 IrisKaggle.Writer ──► CREATE TABLE + batched INSERT (250 rows / 400 KB)
        │
        ▼
 IrisKaggle.Manifest ──► audit row (dataset, file, table, rows, status, timings)
```

Design notes:

* **Streaming CSV.** The file is never loaded into one string. A state machine
  reads logical records (following quoted newlines) and batches them into
  multi-row `INSERT`s, so memory stays flat for large files.
* **Robust writes.** If a batch fails, it is retried row by row; failures are
  collected and reported instead of aborting the load.
* **Type inference.** Columns are sampled (up to 200 rows) and classified as
  `BIGINT`, `DOUBLE`, `BOOLEAN`, `DATE` or a sized `VARCHAR`/`LONGVARCHAR`.
  Values that do not match the inferred type are stored as `NULL`.
* **Only the Python standard library is used** for unzipping, so the stock
  `iris-community` image works without installing anything.
* **Audit trail.** Every import is recorded in `IrisKaggle.Manifest`.

### Type inference

| Sampled values | IRIS type |
| --- | --- |
| `0` / `1` / `true` / `false` | `%Library.Boolean` (0/1) |
| integers | `BIGINT` |
| decimals / exponents | `DOUBLE` |
| `YYYY-MM-DD` | `DATE` |
| anything else | `VARCHAR(255)` or `LONGVARCHAR` by sampled length |

## Limitations

* Datasets behind **competition rules** require you to accept the rules on
  kaggle.com first. If the API refuses the download, download the file manually
  and use `ImportFile`.
* Archives are extracted to a per process temporary directory. They are not
  deleted automatically so that a failed import can be inspected.
* Only CSV files are imported. Archives that contain only parquet or JSON need
  to be converted first.
* Very large archives are bounded by the Kaggle API and by free disk space.

## Development

```
src/cls/IrisKaggle/Utils.cls        identifier + literal helpers
src/cls/IrisKaggle/Credentials.cls  credential resolution
src/cls/IrisKaggle/Client.cls       Kaggle REST client
src/cls/IrisKaggle/TLS.cls          outbound TLS configuration helper
src/cls/IrisKaggle/Archive.cls      zip extraction (Embedded Python stdlib)
src/cls/IrisKaggle/Csv.cls          streaming CSV reader
src/cls/IrisKaggle/Schema.cls       type inference
src/cls/IrisKaggle/Writer.cls       batched INSERT writer
src/cls/IrisKaggle/Importer.cls     orchestration
src/cls/IrisKaggle/Manifest.cls     audit trail
src/cls/IrisKaggle/API.cls          SQL entry points
src/cls/IrisKaggle/CLI.cls          terminal helpers
```

Rebuild after editing sources:

```bash
docker compose up -d --build
```

## License

MIT — see [LICENSE](LICENSE).
