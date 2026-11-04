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
ClassMethod Demo()
{
    Do ..Import("uciml/iris")
}

}
