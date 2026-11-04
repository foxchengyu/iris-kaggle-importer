/// Streaming RFC 4180 style CSV reader. Handles quoted fields, escaped quotes
/// ("") and newlines inside quoted fields, without loading the whole file into
/// memory.
Class IrisKaggle.Csv Extends %RegisteredObject
{

Property Path As %String;

Property Delimiter As %String;

Property QuoteChar As %String;

Property Stream As %Stream.FileCharacter [ Private ];

Property First As %Boolean [ InitialExpression = 1 ];

Method %OnNew(path As %String, delimiter As %String = ",", quoteChar As %String = """") As %Status
{
    Set ..Path = path
    Set ..Delimiter = delimiter
    Set ..QuoteChar = quoteChar
    Set stream = ##class(%Stream.FileCharacter).%New()
    Set sc = stream.LinkToFile(path)
    If $System.Status.IsError(sc) {
        Quit sc
    }
    Try {
        Set stream.TranslateTable = "UTF8"
    } Catch ex {
    }
    Set ..Stream = stream
    Quit $System.Status.OK()
}

/// Reads the next record into <var>fields</var>. Returns 0 at end of file.
Method Next(ByRef fields As %DynamicArray) As %Boolean
{
    Set fields = []
    If '$IsObject(..Stream) {
        Quit 0
    }
    If ..Stream.AtEnd {
        Quit 0
    }
    Set record = ..ReadRecord()
    If ..First {
        Set ..First = 0
        If $Extract(record, 1, 3) = $Char(239, 187, 191) {
            Set record = $Extract(record, 4, $Length(record))
        } ElseIf $Extract(record, 1) = $Char(65279) {
            Set record = $Extract(record, 2, $Length(record))
        }
    }
    Set fields = ..SplitRecord(record)
    Quit 1
}

/// Reads one logical record, following quoted fields across line breaks.
Method ReadRecord() As %String
{
    Set record = ..Stream.ReadLine()
    While ('..Stream.AtEnd) && ('..QuotesBalanced(record)) {
        Set record = record _ $Char(10) _ ..Stream.ReadLine()
    }
    Quit record
}

/// True when every quote in the text is closed.
ClassMethod QuotesBalanced(text As %String) As %Boolean
{
    Set inQuotes = 0
    Set n = $Length(text)
    Set i = 1
    While i <= n {
        If $Extract(text, i) = """" {
            If (inQuotes) && ($Extract(text, i + 1) = """") {
                Set i = i + 1
            } Else {
                Set inQuotes = 'inQuotes
            }
        }
        Set i = i + 1
    }
    Quit 'inQuotes
}

/// Splits a record into fields honouring quotes and escaped quotes.
Method SplitRecord(record As %String) As %DynamicArray
{
    Set out = []
    Set n = $Length(record)
    Set field = ""
    Set inQuotes = 0
    Set i = 1
    While i <= n {
        Set ch = $Extract(record, i)
        If inQuotes {
            If ch = ..QuoteChar {
                If $Extract(record, i + 1) = ..QuoteChar {
                    Set field = field _ ..QuoteChar
                    Set i = i + 1
                } Else {
                    Set inQuotes = 0
                }
            } Else {
                Set field = field _ ch
            }
        } ElseIf ch = ..QuoteChar {
            Set inQuotes = 1
        } ElseIf ch = ..Delimiter {
            Do out.%Push(field)
            Set field = ""
        } Else {
            Set field = field _ ch
        }
        Set i = i + 1
    }
    Do out.%Push(field)
    Quit out
}

}
