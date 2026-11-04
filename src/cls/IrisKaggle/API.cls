/// SQL entry points for the Kaggle importer.
///
///   SELECT IrisKaggle.API_SetCredentials('kaggle_user','0123456789abcdef')
///   SELECT IrisKaggle.API_ImportSimple('uciml/iris')
///   SELECT IrisKaggle.API_ListImports()
Class IrisKaggle.API Extends %RegisteredObject
{

/// Stores Kaggle credentials so that SQL callers do not need environment
/// variables. Returns a JSON status.
ClassMethod SetCredentials(username As %String, apiKey As %String) As %String [ SqlProc ]
{
    Do ##class(IrisKaggle.Credentials).Set(username, apiKey)
    Set out = {}
    Set out.status = "ok"
    Set out.message = "Credentials stored"
    Quit out.%ToJSON()
}

/// Full form. Pass an empty string for targetTable/fileName and 0 for
/// maxRows/version to accept the defaults.
ClassMethod ImportDataset(dataset As %String, targetTable As %String, fileName As %String, maxRows As %Integer, version As %Integer) As %String [ SqlProc ]
{
    Set out = ""
    Try {
        Set stats = ##class(IrisKaggle.Importer).Import(dataset, targetTable, fileName, +maxRows, +version)
        Set out = stats.%ToJSON()
    } Catch ex {
        Set out = ..ErrorJSON(ex.DisplayString())
    }
    Quit out
}

/// One argument form: downloads the dataset and imports its largest CSV.
ClassMethod ImportSimple(dataset As %String) As %String [ SqlProc ]
{
    Set out = ""
    Try {
        Set stats = ##class(IrisKaggle.Importer).Import(dataset)
        Set out = stats.%ToJSON()
    } Catch ex {
        Set out = ..ErrorJSON(ex.DisplayString())
    }
    Quit out
}

/// Imports a CSV that already exists on the IRIS server.
ClassMethod ImportFile(path As %String, targetTable As %String, maxRows As %Integer) As %String [ SqlProc ]
{
    Set out = ""
    Try {
        Set stats = ##class(IrisKaggle.Importer).ImportFile(path, targetTable, +maxRows)
        Set out = stats.%ToJSON()
    } Catch ex {
        Set out = ..ErrorJSON(ex.DisplayString())
    }
    Quit out
}

/// Recent imports as a JSON array.
ClassMethod ListImports() As %String [ SqlProc ]
{
    Set arr = []
    Set stmt = ##class(%SQL.Statement).%New()
    Set sc = stmt.%Prepare("SELECT TOP 50 Dataset, FileName, TargetTable, RowsImported, Status, FinishedAt FROM IrisKaggle.Manifest ORDER BY ID DESC")
    If $System.Status.IsOK(sc) {
        Set rs = stmt.%Execute()
        While rs.%Next() {
            Set row = {}
            Set row.dataset = rs.%Get("Dataset")
            Set row.file = rs.%Get("FileName")
            Set row.table = rs.%Get("TargetTable")
            Set row.rows = rs.%Get("RowsImported")
            Set row.status = rs.%Get("Status")
            Set row.finishedAt = rs.%Get("FinishedAt")
            Do arr.%Push(row)
        }
    }
    Quit arr.%ToJSON()
}

ClassMethod ErrorJSON(message As %String) As %String
{
    Set e = {}
    Set e.status = "error"
    Set e.message = message
    Quit e.%ToJSON()
}

}
