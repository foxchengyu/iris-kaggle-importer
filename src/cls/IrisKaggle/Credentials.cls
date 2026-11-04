/// Resolves Kaggle API credentials. Environment variables win, then the values
/// stored with <method>Set</method>.
Class IrisKaggle.Credentials Extends %RegisteredObject
{

/// Stores credentials in the IRIS database so that SQL callers do not need
/// environment variables.
ClassMethod Set(username As %String, apiKey As %String) As %Status
{
    Set ^IrisKaggle("username") = username
    Set ^IrisKaggle("apikey") = apiKey
    Quit $System.Status.OK()
}

/// Removes stored credentials.
ClassMethod Clear()
{
    Kill ^IrisKaggle("username")
    Kill ^IrisKaggle("apikey")
}

/// Returns 1 when a username and key are available.
ClassMethod Resolve(ByRef username As %String, ByRef apiKey As %String) As %Boolean
{
    Set username = $System.Util.GetEnviron("KAGGLE_USERNAME")
    Set apiKey = $System.Util.GetEnviron("KAGGLE_KEY")
    If username = "" {
        Set username = $Get(^IrisKaggle("username"))
    }
    If apiKey = "" {
        Set apiKey = $Get(^IrisKaggle("apikey"))
    }
    Quit (username '= "") && (apiKey '= "")
}

}
