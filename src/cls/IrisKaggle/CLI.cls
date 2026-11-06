/// Command line helpers for interactive demos:
///
///   Do ##class(IrisKaggle.CLI).Setup("user","key")
///   Do ##class(IrisKaggle.CLI).Demo()
Class IrisKaggle.CLI Extends %RegisteredObject
{

ClassMethod Help()
{
    Write !, "iris-kaggle-importer"
    Write !, "  Do ##class(IrisKaggle.CLI).Setup(""kaggle_user"",""api_key"")"
    Write !, "  Do ##class(IrisKaggle.CLI).Demo()"
    Write !, "  Do ##class(IrisKaggle.CLI).Import(""uciml/iris"")"
    Write !, "  Do ##class(IrisKaggle.CLI).Import(""uciml/iris"","""","""",500)"
    Write !, "  Do ##class(IrisKaggle.CLI).ImportFile(""/data/train.csv"")"
    Write !, "  SELECT IrisKaggle.API_ImportSimple('uciml/iris')"
    Write !
}

/// Stores credentials for the current IRIS instance.
ClassMethod Setup(username As %String, apiKey As %String)
{
    Do ##class(IrisKaggle.Credentials).Set(username, apiKey)
    Write !, "Credentials stored.", !
}

/// Imports a dataset and prints the JSON summary.
ClassMethod Import(dataset As %String, targetTable As %String = "", fileName As %String = "", maxRows As %Integer = 0)
{
    Try {
        Set stats = ##class(IrisKaggle.Importer).Import(dataset, targetTable, fileName, maxRows)
        Write !, stats.%ToJSON(), !
    } Catch ex {
        Write !, "ERROR: ", ex.DisplayString(), !
    }
}

/// Imports a local CSV file and prints the JSON summary.
ClassMethod ImportFile(path As %String, targetTable As %String = "", maxRows As %Integer = 0)
{
    Try {
        Set stats = ##class(IrisKaggle.Importer).ImportFile(path, targetTable, maxRows)
        Write !, stats.%ToJSON(), !
    } Catch ex {
        Write !, "ERROR: ", ex.DisplayString(), !
    }
}

/// Small end to end demo used by the README and the video.
/// When Kaggle credentials are available, imports `uciml/iris` from kaggle.com.
/// Otherwise it imports the bundled sample CSV so the demo still works out of
/// the box and clearly tells the user how to add real credentials.
ClassMethod Demo()
{
    Set hasCreds = ##class(IrisKaggle.Credentials).Resolve(.u, .k)
    If hasCreds {
        Write !, "[Demo] Kaggle credentials found — importing uciml/iris", !
        Do ..Import("uciml/iris")
    } Else {
        Write !, "[Demo] No Kaggle credentials configured.", !
        Write !, "[Demo] Importing local sample CSV instead.", !
        Write !, "[Demo] To import live datasets from Kaggle:", !
        Write !, "[Demo]   1. Get API key — kaggle.com → Settings → API → Create Token", !
        Write !, "[Demo]   2. docker compose exec iris iris session IRIS", !
        Write !, "[Demo]   3. Do ##class(IrisKaggle.CLI).Setup(""user"",""key"")", !
        Write !, "[Demo]   4. Re-run Demo() for uciml/iris", !
        Write !, !
        Do ..ImportFile("/opt/irisapp/demo/sample.csv")
    }
}

}
