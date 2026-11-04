/// Orchestrates a Kaggle -> IRIS import: authenticate, download the dataset
/// archive, extract it, pick a CSV file, infer the schema, create the table and
/// stream the rows in.
Class IrisKaggle.Importer Extends %RegisteredObject
{

/// Imports a Kaggle dataset. <var>dataset</var> is "owner/name", for example
/// "uciml/iris". <var>fileName</var> selects a CSV inside the archive (the
/// largest CSV is used when empty). <var>maxRows</var> of 0 imports everything.
ClassMethod Import(dataset As %String, targetTable As %String = "", fileName As %String = "", maxRows As %Integer = 0, version As %Integer = 0) As %DynamicObject
{
    Set slug = $ZStrip($Get(dataset), "<>W")
    If slug = "" {
        Do ..Fail("A dataset slug is required, for example uciml/iris")
    }
    If slug '[ "/" {
        Do ..Fail("The dataset slug must look like owner/name, for example uciml/iris")
    }
    Set haveCreds = ##class(IrisKaggle.Credentials).Resolve(.username, .apiKey)
    If 'haveCreds {
        Do ..Fail("Kaggle credentials are missing. Set KAGGLE_USERNAME and KAGGLE_KEY, or call ##class(IrisKaggle.Credentials).Set(user,key)")
    }
    Set client = ##class(IrisKaggle.Client).%New(username, apiKey)
    Set workDir = ..WorkDir()
    Set zipPath = workDir _ "/dataset.zip"
    Set bytes = client.Download(slug, zipPath, version)
    Set filesJSON = ##class(IrisKaggle.Archive).Extract(zipPath, workDir _ "/data")
    Set files = ##class(%DynamicArray).%FromJSON(filesJSON)
    Set chosen = ..PickFile(files, fileName)
    If chosen = "" {
        Do ..Fail("No CSV file found in " _ slug _ ". Files: " _ ..FileList(files))
    }
    Set csvPath = workDir _ "/data/" _ chosen
    Quit ..LoadCsv(csvPath, targetTable, maxRows, slug, chosen, bytes)
}

/// Imports a CSV that is already on disk. Useful for competition datasets that
/// must be downloaded manually, and for tests.
ClassMethod ImportFile(csvPath As %String, targetTable As %String = "", maxRows As %Integer = 0) As %DynamicObject
{
    Set name = ##class(%File).GetFilename(csvPath)
    If name = "" {
        Set name = $Piece(csvPath, "/", $Length(csvPath))
    }
    Quit ..LoadCsv(csvPath, targetTable, maxRows, "", name, 0)
}

/// Shared CSV loading pipeline.
ClassMethod LoadCsv(csvPath As %String, targetTable As %String, maxRows As %Integer, dataset As %String, fileName As %String, bytes As %Integer) As %DynamicObject
{
    Set start = $Horolog
    Set exists = ##class(%File).Exists(csvPath)
    If 'exists {
        Do ..Fail("File not found: " _ csvPath)
    }
    Set reader = ##class(IrisKaggle.Csv).%New(csvPath)
    Set header = []
    Set ok = reader.Next(.header)
    If 'ok {
        Do ..Fail("The CSV file is empty: " _ csvPath)
    }
    Set sample = []
    While (sample.%Size() < 200) && (reader.Next(.fields)) {
        Do sample.%Push(fields)
    }
    If (maxRows > 0) && (sample.%Size() > maxRows) {
        Set trimmed = []
        For i = 0:1:maxRows - 1 {
            Do trimmed.%Push(sample.%Get(i))
        }
        Set sample = trimmed
    }
    Set cols = ##class(IrisKaggle.Schema).Build(header, sample)
    If cols.%Size() = 0 {
        Do ..Fail("No columns found in " _ csvPath)
    }
    If targetTable = "" {
        Set targetTable = ..DefaultTable(dataset, fileName)
    }
    Set tableName = ##class(IrisKaggle.Utils).TableName(targetTable)
    Do ..CreateTable(tableName, cols)
    Set errors = []
    Set imported = ##class(IrisKaggle.Writer).InsertRows(tableName, cols, sample, .errors)
    Set done = 0
    If (maxRows > 0) && (imported >= maxRows) {
        Set done = 1
    }
    Set batch = []
    While ('done) && (reader.Next(.fields)) {
        Do batch.%Push(fields)
        If batch.%Size() >= 250 {
            Set batch = ..Trim(batch, maxRows, imported)
            Set imported = imported + ##class(IrisKaggle.Writer).InsertRows(tableName, cols, batch, .errors)
            Set batch = []
            If (maxRows > 0) && (imported >= maxRows) {
                Set done = 1
            }
        }
    }
    If ('done) && (batch.%Size() > 0) {
        Set batch = ..Trim(batch, maxRows, imported)
        Set imported = imported + ##class(IrisKaggle.Writer).InsertRows(tableName, cols, batch, .errors)
    }
    Set stats = {}
    Set stats.status = $Select(errors.%Size() = 0: "ok", 1: "partial")
    Set stats.dataset = dataset
    Set stats.file = fileName
    Set stats.table = tableName
    Set stats.rowsImported = imported
    Set stats.columns = cols.%Size()
    Set stats.failedRows = errors.%Size()
    Set stats.bytesDownloaded = bytes
    Set stats.elapsedSeconds = ##class(IrisKaggle.Utils).ElapsedSeconds(start)
    If errors.%Size() > 0 {
        Set stats.errors = errors
    }
    Do ..Record(dataset, fileName, tableName, cols, imported, bytes, stats.status, "", start)
    Quit stats
}

/// Picks the requested file, or the largest CSV in the archive.
ClassMethod PickFile(files As %DynamicArray, fileName As %String) As %String
{
    Set chosen = ""
    If '$IsObject(files) || (files.%Size() = 0) {
        Quit ""
    }
    If fileName '= "" {
        For i = 0:1:files.%Size() - 1 {
            Set f = files.%Get(i)
            If (f.path = fileName) || (f.path ] fileName) {
                Set chosen = f.path
                Set i = files.%Size()
            }
        }
        Quit chosen
    }
    Set best = -1
    For i = 0:1:files.%Size() - 1 {
        Set f = files.%Get(i)
        If $ZConvert(f.path, "L") ] ".csv" {
            If +f.size > best {
                Set best = +f.size
                Set chosen = f.path
            }
        }
    }
    Quit chosen
}

ClassMethod FileList(files As %DynamicArray) As %String
{
    Set out = ""
    If '$IsObject(files) {
        Quit out
    }
    For i = 0:1:files.%Size() - 1 {
        Set out = out _ $Select(out = "": "", 1: ", ") _ files.%Get(i).path
    }
    Quit out
}

ClassMethod DefaultTable(dataset As %String, fileName As %String) As %String
{
    Set base = $Replace(dataset, "/", "_")
    If base = "" {
        Set base = "local"
    }
    Set stem = $Piece(fileName, ".", 1)
    If stem = "" {
        Set stem = "data"
    }
    Quit "KG_" _ base _ "_" _ stem
}

/// Limits a batch so that the total never exceeds maxRows. Returns the batch
/// unchanged when there is no limit or it already fits.
ClassMethod Trim(rows As %DynamicArray, maxRows As %Integer, imported As %Integer) As %DynamicArray
{
    If (maxRows < 1) || ('$IsObject(rows)) {
        Quit rows
    }
    Set remaining = maxRows - imported
    If remaining >= rows.%Size() {
        Quit rows
    }
    Set out = []
    If remaining < 1 {
        Quit out
    }
    For i = 0:1:remaining - 1 {
        Do out.%Push(rows.%Get(i))
    }
    Quit out
}

/// Per process temporary directory.
ClassMethod WorkDir() As %String
{
    Set tmp = $System.Util.GetEnviron("TMPDIR")
    If tmp = "" {
        Set tmp = $System.Util.GetEnviron("TEMP")
    }
    If tmp = "" {
        Set tmp = $System.Util.GetEnviron("TMP")
    }
    If tmp = "" {
        Set tmp = "/tmp"
    }
    Set dir = tmp _ "/iriskaggle_" _ $Job _ "_" _ $Piece($Horolog, ",", 2)
    Do ##class(%File).CreateDirectoryChain(dir)
    Quit dir
}

ClassMethod CreateTable(tableName As %String, cols As %DynamicArray) As %Status
{
    Set stmt = ##class(%SQL.Statement).%New()
    Set sc = stmt.%Prepare("DROP TABLE IF EXISTS " _ tableName)
    If $System.Status.IsOK(sc) {
        Set rs = stmt.%Execute()
    }
    Set sql = ##class(IrisKaggle.Schema).DDL(tableName, cols)
    Set sc = stmt.%Prepare(sql)
    If $System.Status.IsError(sc) {
        Do ..Fail("Could not prepare DDL: " _ $System.Status.GetErrorText(sc))
    }
    Set rs = stmt.%Execute()
    If rs.%SQLCODE < 0 {
        Do ..Fail("Could not create table: " _ rs.%Message)
    }
    Quit $System.Status.OK()
}

/// Writes an audit row. Failures here never abort an import.
ClassMethod Record(dataset As %String, fileName As %String, tableName As %String, cols As %DynamicArray, imported As %Integer, bytes As %Integer, status As %String, message As %String, start As %String)
{
    Try {
        Set m = ##class(IrisKaggle.Manifest).%New()
        Set m.Dataset = dataset
        Set m.FileName = fileName
        Set m.TargetTable = tableName
        Set m.Columns = cols.%ToJSON()
        Set m.RowsImported = imported
        Set m.BytesDownloaded = bytes
        Set m.Status = status
        Set m.Message = message
        Set m.StartedAt = $ZDateTime(start, 3)
        Set m.FinishedAt = ##class(IrisKaggle.Utils).Now()
        Do m.%Save()
    } Catch ex {
    }
}

ClassMethod Fail(message As %String)
{
    Throw ##class(%Exception.General).%New("IrisKaggle.Importer", 6003, "", message)
}

}
