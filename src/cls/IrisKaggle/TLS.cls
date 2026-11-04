/// Outbound TLS helper.
///
/// Some IRIS installations, including several community images, ship without
/// any SSL configuration. In that state every HTTPS call fails with error
/// #6159 ("no SSLConfiguration is specified"), so the importer would not work
/// out of the box. This class creates a plain client configuration on demand.
///
/// The configuration created here is the stock one: TLS as a client, no client
/// certificate, and the operating system trust store for server verification.
/// Nothing is changed when a configuration with the same name already exists.
Class IrisKaggle.TLS Extends %RegisteredObject
{

/// Name used when the caller does not pass one.
Parameter DEFAULTNAME = "IrisKaggleTLS";

/// Returns the name of a usable client TLS configuration, creating it when it
/// is missing. Returns an empty string when no configuration can be used, in
/// which case the caller should let IRIS report its own TLS error.
ClassMethod Ensure(name As %String = "") As %String
{
    Set name = $Select(name = "": ..#DEFAULTNAME, 1: name)
    If ..Exists(name) {
        Quit name
    }
    Set previous = $Namespace
    Set created = 0
    Try {
        Set $Namespace = "%SYS"
        If '##class(Security.SSLConfigs).Exists(name) {
            Do ##class(Security.SSLConfigs).Create(name)
        }
        Set created = ##class(Security.SSLConfigs).Exists(name)
    } Catch ex {
        Set created = 0
    }
    Set $Namespace = previous
    Quit $Select(created: name, 1: "")
}

/// True when a configuration with this name exists. Security classes live in
/// the %SYS namespace, so the lookup is done there and the caller namespace is
/// restored afterwards.
ClassMethod Exists(name As %String) As %Boolean
{
    If name = "" {
        Quit 0
    }
    Set previous = $Namespace
    Set found = 0
    Try {
        Set $Namespace = "%SYS"
        If ##class(Security.SSLConfigs).Exists(name) {
            Set found = 1
        }
    } Catch ex {
        Set found = 0
    }
    Set $Namespace = previous
    Quit found
}

}
