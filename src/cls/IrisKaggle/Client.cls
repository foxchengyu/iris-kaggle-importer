/// REST client for the Kaggle API (https://www.kaggle.com/docs/api).
/// Uses HTTP basic authentication with the username and API key.
Class IrisKaggle.Client Extends %RegisteredObject
{

Property Endpoint As %String [ InitialExpression = "https://www.kaggle.com/api/v1" ];

Property Username As %String;

Property ApiKey As %String;

Property Timeout As %Integer [ InitialExpression = 120 ];

Property MaxRetries As %Integer [ InitialExpression = 3 ];

/// Name of the SSL configuration used for https calls. When empty, a client
/// configuration is created on demand by <class>IrisKaggle.TLS</class>.
Property SSLConfiguration As %String;

/// Optional HTTP proxy, for example "http://127.0.0.1:7890" or
/// "proxy.example.com:8080". Read from KAGGLE_PROXY when not set.
Property Proxy As %String;

Property Scheme As %String [ Private ];
Property Host As %String [ Private ];
Property Port As %Integer [ Private ];
Property BasePath As %String [ Private ];

/// Name of the TLS configuration that was actually resolved, cached after the
/// first request.
Property ResolvedSSL As %String [ Private ];

Method %OnNew(username As %String = "", apiKey As %String = "") As %Status
{
    If (username = "") || (apiKey = "") {
        Do ##class(IrisKaggle.Credentials).Resolve(.u, .k)
        If username = "" {
            Set username = u
        }
        If apiKey = "" {
            Set apiKey = k
        }
    }
    Set ..Username = username
    Set ..ApiKey = apiKey
    Set ..Proxy = $System.Util.GetEnviron("KAGGLE_PROXY")
    Do ..ParseEndpoint(..Endpoint)
    Quit $System.Status.OK()
}

Method ParseEndpoint(url As %String) As %Status
{
    Set u = $ZStrip($Get(url), "<>W")
    Set ..Scheme = "https"
    If $Extract(u, 1, 8) = "https://" {
        Set rest = $Extract(u, 9, $Length(u))
    } ElseIf $Extract(u, 1, 7) = "http://" {
        Set ..Scheme = "http"
        Set rest = $Extract(u, 8, $Length(u))
    } Else {
        Set rest = u
    }
    Set hostPort = $Piece(rest, "/", 1)
    Set pathPart = $Piece(rest, "/", 2, $Length(rest))
    Set ..BasePath = $Select(pathPart = "": "", 1: "/" _ pathPart)
    Set ..Port = $Select(..Scheme = "https": 443, 1: 80)
    If hostPort [ ":" {
        Set p = $Piece(hostPort, ":", 2)
        If p '= "" {
            Set ..Port = +p
        }
        Set ..Host = $Piece(hostPort, ":", 1)
    } Else {
        Set ..Host = hostPort
    }
    Quit $System.Status.OK()
}

/// Metadata of one dataset, including the file list.
Method View(ownerSlug As %String)
{
    Quit ..GetJSON("/datasets/view/" _ ownerSlug)
}

/// Dataset search.
Method List(search As %String = "", page As %Integer = 1)
{
    Set path = "/datasets/list"
    Set qs = "?page=" _ page
    If search '= "" {
        Set qs = qs _ "&search=" _ ##class(IrisKaggle.Utils).UrlEncode(search)
    }
    Quit ..GetJSON(path _ qs)
}

/// Downloads a dataset archive to <var>targetPath</var> and returns its size
/// in bytes.
Method Download(ownerSlug As %String, targetPath As %String, version As %Integer = 0) As %Integer
{
    Set path = "/datasets/download/" _ ownerSlug
    If version > 0 {
        Set path = path _ "?datasetVersionNumber=" _ version
    }
    Set http = ..NewRequest()
    Set http.FollowRedirect = 1
    Set http.AcceptGzip = 0
    Set sc = http.Get(..BasePath _ path)
    If $System.Status.IsError(sc) {
        Do ..Raise("Transport error downloading " _ ownerSlug _ ": " _ $System.Status.GetErrorText(sc))
    }
    Set resp = http.HttpResponse
    If resp.StatusCode '= 200 {
        Set body = ..ReadStream(resp.Data)
        Do ..Raise("Kaggle returned HTTP " _ resp.StatusCode _ " for " _ ownerSlug _ ": " _ $Extract(body, 1, 400))
    }
    If '$IsObject(resp.Data) {
        Do ..Raise("Kaggle returned an empty archive for " _ ownerSlug)
    }
    Set file = ##class(%Stream.FileBinary).%New()
    Set sc = file.LinkToFile(targetPath)
    If $System.Status.IsError(sc) {
        Do ..Raise("Cannot write to " _ targetPath _ ": " _ $System.Status.GetErrorText(sc))
    }
    Do file.CopyFrom(resp.Data)
    Set sc = file.%Save()
    If $System.Status.IsError(sc) {
        Do ..Raise("Cannot save " _ targetPath _ ": " _ $System.Status.GetErrorText(sc))
    }
    Quit file.Size
}

Method GetJSON(path As %String)
{
    Set attempt = 0
    Set delay = 2
    Set result = ""
    While attempt < ..MaxRetries {
        Set attempt = attempt + 1
        Set http = ..NewRequest()
        Do http.SetHeader("Accept", "application/json")
        Set sc = http.Get(..BasePath _ path)
        If $System.Status.IsError(sc) {
            If attempt >= ..MaxRetries {
                Do ..Raise("Transport error calling " _ path _ ": " _ $System.Status.GetErrorText(sc))
            }
            Hang delay
            Set delay = delay * 2
            Continue
        }
        Set resp = http.HttpResponse
        Set body = ..ReadStream(resp.Data)
        If resp.StatusCode = 200 {
            Set obj = ""
            Try {
                Set obj = ##class(%DynamicObject).%FromJSON(body)
            } Catch ex {
                Set obj = ""
            }
            If '$IsObject(obj) {
                Do ..Raise("Invalid JSON returned by " _ path _ ": " _ $Extract(body, 1, 200))
            }
            Set result = obj
            Quit
        }
        If ((resp.StatusCode = 429) || (resp.StatusCode >= 500)) && (attempt < ..MaxRetries) {
            Hang delay
            Set delay = delay * 2
            Continue
        }
        Do ..Raise("Kaggle returned HTTP " _ resp.StatusCode _ " for " _ path _ ": " _ $Extract(body, 1, 400))
    }
    If $IsObject(result) {
        Quit result
    }
    Do ..Raise("Request failed after " _ ..MaxRetries _ " attempts: " _ path)
    Quit ""
}

Method NewRequest() As %Net.HttpRequest
{
    Set http = ##class(%Net.HttpRequest).%New()
    Set http.Server = ..Host
    Set http.Port = ..Port
    Set http.Https = (..Scheme = "https")
    If http.Https {
        Set tls = ..ResolveSSL()
        If tls '= "" {
            Set http.SSLConfiguration = tls
        }
    }
    Do ..ApplyProxy(http)
    Set http.Timeout = ..Timeout
    Set http.FollowRedirect = 1
    Do http.SetHeader("User-Agent", "iris-kaggle-importer/1.0")
    If (..Username '= "") && (..ApiKey '= "") {
        Do http.SetHeader("Authorization", "Basic " _ $System.Encryption.Base64Encode(..Username _ ":" _ ..ApiKey))
    }
    Quit http
}

/// Returns the TLS configuration to use, creating a client one when the
/// installation has none.
Method ResolveSSL() As %String
{
    If ..ResolvedSSL '= "" {
        Quit ..ResolvedSSL
    }
    Set name = ##class(IrisKaggle.TLS).Ensure(..SSLConfiguration)
    If (name = "") && ##class(IrisKaggle.TLS).Exists("Default") {
        Set name = "Default"
    }
    Set ..ResolvedSSL = name
    Quit name
}

/// Points the request at the configured proxy. HTTPS traffic goes through an
/// HTTP CONNECT tunnel, so both ProxyTunnel and ProxyHTTPS are required.
Method ApplyProxy(http As %Net.HttpRequest)
{
    If ..Proxy = "" {
        Quit
    }
    Set addr = ..Proxy
    If addr [ "://" {
        Set addr = $Piece(addr, "://", 2)
    }
    Set addr = $Piece(addr, "/", 1)
    Set host = addr
    Set port = 8080
    If addr [ ":" {
        Set host = $Piece(addr, ":", 1)
        Set port = +$Piece(addr, ":", 2)
    }
    If host = "" {
        Quit
    }
    Set http.ProxyServer = host
    Set http.ProxyPort = port
    Set http.ProxyTunnel = 1
    Set http.ProxyHTTPS = 1
}

ClassMethod ReadStream(stream As %Stream.Object) As %String
{
    If '$IsObject(stream) {
        Quit ""
    }
    Set out = ""
    Do stream.Rewind()
    While 'stream.AtEnd {
        Set out = out _ stream.Read(32768)
    }
    Quit out
}

Method Raise(message As %String) As %Status
{
    Throw ##class(%Exception.General).%New("IrisKaggle.Client", 6001, "", message)
    Quit $System.Status.Error(6001, message)
}

}
