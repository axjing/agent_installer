$root = Split-Path $PSScriptRoot -Parent
$files = Get-ChildItem -Path $root -Recurse -Include *.ps1,*.psm1

$utf8Bom = New-Object System.Text.UTF8Encoding($true)

foreach ($f in $files) {
    if ($f.FullName -like "*tests*") { continue }
    $text = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($f.FullName, $text, $utf8Bom)
}
Write-Host "All source files converted to UTF-8 with BOM."
