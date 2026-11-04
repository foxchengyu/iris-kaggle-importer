/// Zip extraction for downloaded Kaggle archives. Implemented with the Python
/// standard library (zipfile) that ships with InterSystems Embedded Python, so
/// no pip packages are required.
Class IrisKaggle.Archive Extends %RegisteredObject
{

/// Extracts <var>zipPath</var> into <var>targetDir</var> and returns a JSON
/// array of objects: [{"path":"train.csv","size":12345}, ...].
/// Entries that would escape the target directory are skipped.
ClassMethod Extract(zipPath As %String, targetDir As %String) As %String [ Language = python ]
{
    import json
    import os
    import zipfile

    os.makedirs(targetDir, exist_ok=True)
    base = os.path.abspath(targetDir)
    files = []

    with zipfile.ZipFile(zipPath) as archive:
        for info in archive.infolist():
            if info.is_dir():
                continue
            name = info.filename.replace("\\", "/")
            if name.startswith("__MACOSX/"):
                continue
            target = os.path.abspath(os.path.join(base, name))
            if not target.startswith(base + os.sep):
                continue
            parent = os.path.dirname(target)
            if parent:
                os.makedirs(parent, exist_ok=True)
            with archive.open(info) as source:
                with open(target, "wb") as destination:
                    destination.write(source.read())
            files.append({"path": name, "size": info.file_size})

    return json.dumps(files)
}

}
