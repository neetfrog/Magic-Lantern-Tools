# Magic Lantern MLV Importer

Automatic SD/CF card importer for **Windows 11**.

Copies:

* `.CR2`, `.CR3`, `.JPG`, `.JPEG`, etc. → Photos folder
* `.MLV`, `.M00`, `.M01`, `.M02`, etc. → MLV folder

The original card files are **never deleted or moved**.

## Files

```text
MLV-Importer\
├── MLV-Importer.ps1
├── config.json
├── Start-MLV-Importer.cmd
├── Run-Once.cmd
├── logs\
└── manifests\
```

## Setup

1. Create a folder, e.g.

```text
C:\MLV-Importer
```

2. Put the files above inside it.

3. Edit `config.json`:

```json
"Destinations": {
    "Photos": "D:\\Camera Import\\Photos",
    "MLV": "D:\\Camera Import\\MLV"
}
```

4. Double-click:

```text
Start-MLV-Importer.cmd
```

The program will wait for an SD/CF card.

## Test first

Set:

```json
"DryRun": true
```

in `config.json`.

This shows what would be imported without copying anything.

When ready:

```json
"DryRun": false
```

## MLV

Split recordings are handled automatically:

```text
MVI_0001.MLV
MVI_0001.M00
MVI_0001.M01
MVI_0001.M02
```

Files are copied without renaming or modifying them.

## Verification

Default:

```json
"Method": "Size"
```

For stronger verification:

```json
"Method": "SHA256"
```

SHA-256 is slower, especially with large MLV files.

## Logs

Import logs:

```text
logs\importer.log
```

## Automatic startup

Press `Win + R`, enter:

```text
shell:startup
```

Put a shortcut to `Start-MLV-Importer.cmd` there.

That's it — insert an SD/CF card and the importer handles the rest.
