/// Helpers shared by the importer: identifier sanitising, SQL literal quoting,
/// numeric validation and small formatting utilities.
Class IrisKaggle.Utils Extends %RegisteredObject
{

/// IRIS SQL reserved words. A column whose sanitised name matches one of these
/// gets a "_C" suffix so that it can be used without delimited identifiers.
Parameter RESERVED = ",ADD,ALL,ALTER,AND,ANY,AS,ASC,AVG,BEGIN,BETWEEN,BIGINT,BINARY,BIT,BLOB,BOOLEAN,BY,CALL,CASE,CAST,CHAR,CHECK,CLOB,CLOSE,COLUMN,COMMIT,CONSTRAINT,COUNT,CREATE,CROSS,CURSOR,DATE,DAY,DECIMAL,DECLARE,DEFAULT,DELETE,DESC,DISTINCT,DO,DOUBLE,DROP,ELSE,END,ESCAPE,EXCEPT,EXEC,EXECUTE,EXISTS,EXPLAIN,FALSE,FETCH,FLOAT,FOR,FOREIGN,FROM,FULL,FUNCTION,GRANT,GROUP,HAVING,HOUR,IF,IN,INDEX,INNER,INSERT,INT,INTEGER,INTERSECT,INTERVAL,INTO,IS,JOIN,KEY,LANGUAGE,LEFT,LIKE,LIMIT,LOCK,LONGVARCHAR,MAX,MERGE,METHOD,MIN,MINUTE,MONTH,NATURAL,NOT,NULL,NUMERIC,OFFSET,ON,OPEN,OR,ORDER,OUTER,PRECISION,PRIMARY,PROCEDURE,PROPERTY,PUBLIC,QUERY,REAL,REFERENCES,REPLACE,RESIGNAL,RETURN,RETURNS,REVOKE,RIGHT,ROLLBACK,ROW,ROWID,ROWS,SAMPLE,SCHEMA,SECOND,SELECT,SET,SHOW,SIGNAL,SMALLINT,SOME,SUM,TABLE,TEXT,THEN,TIME,TIMESTAMP,TO,TOP,TRANSACTION,TRIGGER,TRUE,TRUNCATE,UNION,UNIQUE,UNLOCK,UPDATE,USER,USING,VALUE,VALUES,VARCHAR,VARBINARY,VIEW,WHEN,WHERE,WHILE,YEAR";

/// Returns true when <var>name</var> is an IRIS SQL reserved word.
ClassMethod IsReserved(name As %String) As %Boolean
{
    Quit (..#RESERVED [ ("," _ $ZConvert(name, "U") _ ","))
}

/// Turns an arbitrary column or dataset name into a safe, unquoted IRIS SQL
/// identifier. Non ASCII characters, punctuation and spaces become "_".
ClassMethod Ident(name As %String, maxLen As %Integer = 60) As %String
{
    Set src = $ZStrip($Get(name), "<>W")
    If src = "" {
        Set src = "col"
    }
    Set out = ""
    Set n = $Length(src)
    For i = 1:1:n {
        Set ch = $Extract(src, i)
        If ((ch ? 1A) || (ch ? 1N) || (ch = "_")) {
            Set out = out _ ch
        } Else {
            Set out = out _ "_"
        }
    }
    While out [ "__" {
        Set out = $Replace(out, "__", "_")
    }
    Set out = $ZStrip(out, "<>", "_")
    If out = "" {
        Set out = "col"
    }
    Set first = $Extract(out, 1)
    If '(first ? 1A) {
        Set out = "C_" _ out
    }
    If $Length(out) > maxLen {
        Set out = $Extract(out, 1, maxLen)
    }
    If ..IsReserved(out) {
        Set out = $Extract(out, 1, maxLen - 2) _ "_C"
    }
    Quit out
}

/// Sanitises a possibly schema qualified table name ("Schema.Table").
ClassMethod TableName(spec As %String) As %String
{
    Set spec = $ZStrip($Get(spec), "<>W")
    If spec [ "." {
        Set schema = ..Ident($Piece(spec, ".", 1))
        Set table = ..Ident($Piece(spec, ".", 2))
        Quit schema _ "." _ table
    }
    Quit ..Ident(spec)
}

/// Quotes a value as an IRIS SQL string literal.
ClassMethod Quote(value As %String) As %String
{
    Set v = $Translate(value, $Char(0))
    Set v = $Replace(v, "'", "''")
    Quit "'" _ v _ "'"
}

/// True when the string looks like a number IRIS can store in a numeric
/// column. Accepts an optional sign and an optional exponent.
ClassMethod IsNumber(value As %String) As %Boolean
{
    Set v = $ZStrip($Get(value), "<>W")
    If v = "" {
        Quit 0
    }
    If ($Extract(v, 1) = "-") || ($Extract(v, 1) = "+") {
        Set v = $Extract(v, 2, $Length(v))
    }
    If v = "" {
        Quit 0
    }
    If v ? 1.N {
        Quit 1
    }
    If v ? 1.N1"."1.N {
        Quit 1
    }
    If v ? 1"."1.N {
        Quit 1
    }
    Set epos = $Locate(v, "E")
    If epos = 0 {
        Set epos = $Locate(v, "e")
    }
    If epos > 0 {
        Set mant = $Extract(v, 1, epos - 1)
        Set exp = $Extract(v, epos + 1, $Length(v))
        If ($Extract(exp, 1) = "-") || ($Extract(exp, 1) = "+") {
            Set exp = $Extract(exp, 2, $Length(exp))
        }
        If (exp ? 1.N) && ((mant ? 1.N) || (mant ? 1.N1"."1.N) || (mant ? 1"."1.N)) {
            Quit 1
        }
    }
    Quit 0
}

/// Percent encodes a value, treating it as UTF-8.
ClassMethod UrlEncode(value As %String) As %String
{
    Set s = $ZConvert(value, "O", "UTF8")
    Set out = ""
    For i = 1:1:$Length(s) {
        Set c = $Extract(s, i)
        Set a = $Ascii(c)
        If ((a >= 65) && (a <= 90)) || ((a >= 97) && (a <= 122)) || ((a >= 48) && (a <= 57)) || (a = 45) || (a = 95) || (a = 46) || (a = 126) {
            Set out = out _ c
        } Else {
            Set h = $ZHex(a)
            If $Length(h) < 2 {
                Set h = "0" _ h
            }
            Set out = out _ "%" _ h
        }
    }
    Quit out
}

/// True when the string is a plain integer.
ClassMethod IsInteger(value As %String) As %Boolean
{
    Set v = $ZStrip($Get(value), "<>W")
    If v = "" {
        Quit 0
    }
    If ($Extract(v, 1) = "-") || ($Extract(v, 1) = "+") {
        Set v = $Extract(v, 2, $Length(v))
    }
    Quit (v '= "") && (v ? 1.N)
}

/// True for ISO dates (YYYY-MM-DD).
ClassMethod IsDate(value As %String) As %Boolean
{
    Set v = $ZStrip($Get(value), "<>W")
    Quit (v ? 4N1"-"2N1"-"2N)
}

/// Current local time as an IRIS timestamp.
ClassMethod Now() As %String
{
    Quit $ZDateTime($Horolog, 3)
}

/// Whole seconds elapsed since <var>startHorolog</var>.
ClassMethod ElapsedSeconds(startHorolog As %String) As %Integer
{
    Quit ($Piece($Horolog, ",", 1) - $Piece(startHorolog, ",", 1)) * 86400 + ($Piece($Horolog, ",", 2) - $Piece(startHorolog, ",", 2))
}

}
