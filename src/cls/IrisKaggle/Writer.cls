/// Writes CSV rows into an IRIS table using batched INSERT statements, with a
/// row by row fallback so a single bad value cannot abort an import.
Class IrisKaggle.Writer Extends %RegisteredObject
{

Parameter MAXROWS = 200;

Parameter MAXBYTES = 200000;

/// Inserts all rows and returns how many were written. Failures are collected
/// in <var>errors</var>.
ClassMethod InsertRows(tableName As %String, cols As %DynamicArray, rows As %DynamicArray, ByRef errors As %DynamicArray) As %Integer
{
    If '$IsObject(errors) {
        Set errors = []
    }
    Set inserted = 0
    Set total = rows.%Size()
    Set i = 0
    Set colList = ..ColumnList(cols)
    While i < total {
        Set buf = ""
        Set count = 0
        While (i < total) && (count < ..#MAXROWS) && ($Length(buf) < ..#MAXBYTES) {
            Set buf = buf _ $Select(buf = "": "", 1: ",") _ ..Tuple(cols, rows.%Get(i))
            Set i = i + 1
            Set count = count + 1
        }
        Set sql = "INSERT INTO " _ tableName _ " (" _ colList _ ") VALUES " _ buf
        Set sc = ..Exec(sql)
        If $System.Status.IsOK(sc) {
            Set inserted = inserted + count
        } Else {
            Set inserted = inserted + ..InsertOneByOne(tableName, colList, cols, rows, i - count, count, .errors)
        }
    }
    Quit inserted
}

ClassMethod InsertOneByOne(tableName As %String, colList As %String, cols As %DynamicArray, rows As %DynamicArray, startIdx As %Integer, count As %Integer, ByRef errors As %DynamicArray) As %Integer
{
    Set ok = 0
    For j = startIdx:1:(startIdx + count - 1) {
        Set sql = "INSERT INTO " _ tableName _ " (" _ colList _ ") VALUES " _ ..Tuple(cols, rows.%Get(j))
        Set sc = ..Exec(sql)
        If $System.Status.IsOK(sc) {
            Set ok = ok + 1
        } ElseIf errors.%Size() < 20 {
            Set e = {}
            Set e.row = j
            Set e.message = $System.Status.GetErrorText(sc)
            Do errors.%Push(e)
        }
    }
    Quit ok
}

ClassMethod Exec(sql As %String) As %Status
{
    Set stmt = ##class(%SQL.Statement).%New()
    Set sc = stmt.%Prepare(sql)
    If $System.Status.IsError(sc) {
        Quit sc
    }
    Set rs = stmt.%Execute()
    If rs.%SQLCODE < 0 {
        Quit $System.Status.Error(6002, rs.%Message)
    }
    Quit $System.Status.OK()
}

ClassMethod ColumnList(cols As %DynamicArray) As %String
{
    Set out = ""
    For i = 0:1:cols.%Size() - 1 {
        Set out = out _ $Select(out = "": "", 1: ",") _ cols.%Get(i).name
    }
    Quit out
}

ClassMethod Tuple(cols As %DynamicArray, row As %DynamicArray) As %String
{
    Set out = "("
    For i = 0:1:cols.%Size() - 1 {
        Set c = cols.%Get(i)
        Set v = ""
        If $IsObject(row) {
            Set v = row.%Get(c.index)
        }
        Set out = out _ $Select(i = 0: "", 1: ",") _ ..Render(c, v)
    }
    Quit out _ ")"
}

/// Renders one CSV value as a SQL literal for the column kind.
ClassMethod Render(col As %DynamicObject, value) As %String
{
    Set kind = col.kind
    Set v = value
    If kind = "int" {
        If v = "" {
            Quit "NULL"
        }
        If '##class(IrisKaggle.Utils).IsInteger(v) {
            Quit "NULL"
        }
        Quit v
    }
    If kind = "float" {
        If v = "" {
            Quit "NULL"
        }
        If '##class(IrisKaggle.Utils).IsNumber(v) {
            Quit "NULL"
        }
        Quit v
    }
    If kind = "bool" {
        If v = "" {
            Quit "NULL"
        }
        Set lv = $ZConvert(v, "L")
        If (lv = "true") || (lv = "1") {
            Quit "1"
        }
        Quit "0"
    }
    If kind = "date" {
        If '##class(IrisKaggle.Utils).IsDate(v) {
            Quit "NULL"
        }
        // IRIS DATE expects its display format, so convert the ISO text explicitly.
        Quit "TO_DATE(" _ ##class(IrisKaggle.Utils).Quote(v) _ ",'YYYY-MM-DD')"
    }
    Quit ##class(IrisKaggle.Utils).Quote(v)
}

}
