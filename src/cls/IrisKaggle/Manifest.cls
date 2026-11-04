/// Audit trail of every Kaggle dataset import.
Class IrisKaggle.Manifest Extends %Persistent
{

Property Dataset As %String(MAXLEN=512);

Property FileName As %String(MAXLEN=512);

Property TargetTable As %String(MAXLEN=255);

Property Columns As %String(MAXLEN=4000);

Property RowsImported As %Integer;

Property BytesDownloaded As %Integer;

Property Status As %String(MAXLEN=32);

Property Message As %String(MAXLEN=4000);

Property StartedAt As %TimeStamp;

Property FinishedAt As %TimeStamp;

Index DatasetIdx On Dataset;

}
