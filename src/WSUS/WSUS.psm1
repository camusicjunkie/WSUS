#Requires -Version 5.1
# Root module: dot-source every Private then Public function. What is exported is decided by
# FunctionsToExport in WSUS.psd1 (hand-listed), not here.

$privateFiles = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Private') -Filter '*.ps1' -File -ErrorAction SilentlyContinue)
$publicFiles = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public') -Filter '*.ps1' -File -ErrorAction SilentlyContinue)

foreach ($file in @($privateFiles + $publicFiles)) {
    . $file.FullName
}
