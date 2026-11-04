/// Infers IRIS column types from a sample of CSV rows.
Class IrisKaggle.Schema Extends %RegisteredObject
{

/// Builds column descriptors from the header and the sampled rows.
ClassMethod Build(header As %DynamicArray, sample As %DynamicArray) As %DynamicArray
{
    Set cols = []
    Set used = ","
    If '$IsObject(header) {
        Quit cols
    }
    For i = 0:1:header.%Size() - 1 {
        Set raw = header.%Get(i)
        If $ZStrip(raw, "<>W") = "" {
            Set raw = "col_" _ (i + 1)
        }
        Set col = {}
        Set col.index = i
        Set col.source = raw
        Set col.name = ..Unique(##class(IrisKaggle.Utils).Ident(raw), .used)
        Set kind = ..InferKind(sample, i)
        Set col.kind = kind
        Set col.type = ..TypeFor(kind, ..MaxLen(sample, i))
        Do cols.%Push(col)
    }
    Quit cols
}

/// Guesses int/float/bool/date/string from the non empty sampled values.
ClassMethod InferKind(sample As %DynamicArray, idx As %Integer) As %String
{
    Set seen = 0
    Set isInt = 1
    Set isNum = 1
    Set isBool = 1
    Set isDate = 1
    If '$IsObject(sample) {
        Quit "string"
    }
    For r = 0:1:sample.%Size() - 1 {
        Set row = sample.%Get(r)
        If '$IsObject(row) {
            Continue
        }
        Set v = row.%Get(idx)
        If v = "" {
            Continue
        }
        Set seen = seen + 1
        If '##class(IrisKaggle.Utils).IsInteger(v) {
            Set isInt = 0
        }
        If '##class(IrisKaggle.Utils).IsNumber(v) {
            Set isNum = 0
        }
        Set lv = $ZConvert(v, "L")
        If (lv '= "true") && (lv '= "false") && (lv '= "0") && (lv '= "1") {
            Set isBool = 0
        }
        If '##class(IrisKaggle.Utils).IsDate(v) {
            Set isDate = 0
        }
    }
    If seen = 0 {
        Quit "string"
    }
    If isBool {
        Quit "bool"
    }
    If isInt {
        Quit "int"
    }
    If isNum {
        Quit "float"
    }
    If isDate {
        Quit "date"
    }
    Quit "string"
}

/// Maps an inferred kind to an IRIS SQL type.
ClassMethod TypeFor(kind As %String, maxLen As %Integer) As %String
{
    If kind = "bool" {
        Quit "%Library.Boolean"
    }
    If kind = "int" {
        Quit "BIGINT"
    }
    If kind = "float" {
        Quit "DOUBLE"
    }
    If kind = "date" {
        Quit "DATE"
    }
    // Short sampled values are treated as categories; longer ones become a CLOB
    // so that no later row can overflow the column.
    If maxLen <= 255 {
        Quit "VARCHAR(255)"
    }
    Quit "LONGVARCHAR"
}

/// Longest sampled value for one column.
ClassMethod MaxLen(sample As %DynamicArray, idx As %Integer) As %Integer
{
    Set max = 0
    If '$IsObject(sample) {
        Quit 0
    }
    For r = 0:1:sample.%Size() - 1 {
        Set row = sample.%Get(r)
        If '$IsObject(row) {
            Continue
        }
        Set len = $Length(row.%Get(idx))
        If len > max {
            Set max = len
        }
    }
    Quit max
}

/// Ensures a column name is unique (case insensitive).
ClassMethod Unique(name As %String, ByRef used As %String) As %String
{
    Set candidate = name
    Set n = 1
    While used [ ("," _ $ZConvert(candidate, "U") _ ",") {
        Set n = n + 1
        Set candidate = name _ "_" _ n
    }
    Set used = used _ $ZConvert(candidate, "U") _ ","
    Quit candidate
}

/// Renders the CREATE TABLE statement.
ClassMethod DDL(tableName As %String, cols As %DynamicArray) As %String
{
    Set parts = ""
    For i = 0:1:cols.%Size() - 1 {
        Set c = cols.%Get(i)
        Set parts = parts _ $Select(parts = "": "", 1: ", ") _ c.name _ " " _ c.type
    }
    Quit "CREATE TABLE " _ tableName _ " (" _ parts _ ")"
}

}
