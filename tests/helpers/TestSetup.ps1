# Dot-source from BeforeAll in every test file (adjust the ..\ depth to the test file):
#   BeforeAll { . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1') }
#   AfterAll  { Remove-WsusTestEnvironment }
# Puts tests/stubs on PSModulePath (so Get-Module -ListAvailable finds the stubs), imports the stub
# modules and the WSUS module from src/, and loads New-FakeWsusServer.

$script:TestsRoot = Split-Path -Parent $PSScriptRoot
$script:RepoRoot = Split-Path -Parent $script:TestsRoot
$script:StubsRoot = Join-Path $script:TestsRoot 'stubs'
$script:ModuleManifest = Join-Path $script:RepoRoot 'src\WSUS\WSUS.psd1'
$script:StubNames = 'UpdateServices', 'ActiveDirectory', 'WebAdministration', 'ServerManager'

if (-not $env:WSUS_TEST_ORIGINAL_PSMODULEPATH) {
    $env:WSUS_TEST_ORIGINAL_PSMODULEPATH = $env:PSModulePath
}
$env:PSModulePath = $script:StubsRoot + ';' + $env:WSUS_TEST_ORIGINAL_PSMODULEPATH

foreach ($stub in $script:StubNames) {
    Import-Module -Name (Join-Path $script:StubsRoot $stub) -Force -Global -DisableNameChecking
}
Import-Module -Name $script:ModuleManifest -Force -Global

. (Join-Path $PSScriptRoot 'New-FakeWsusServer.ps1')

function Remove-WsusTestEnvironment {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Test teardown helper; ShouldProcess adds nothing.')]
    param ()
    Remove-Module -Name WSUS -Force -ErrorAction SilentlyContinue
    Remove-Module -Name $script:StubNames -Force -ErrorAction SilentlyContinue
    if ($env:WSUS_TEST_ORIGINAL_PSMODULEPATH) {
        $env:PSModulePath = $env:WSUS_TEST_ORIGINAL_PSMODULEPATH
        Remove-Item -Path Env:\WSUS_TEST_ORIGINAL_PSMODULEPATH
    }
}
