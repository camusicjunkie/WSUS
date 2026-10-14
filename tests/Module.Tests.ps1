BeforeDiscovery {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:publicNames = @(Get-ChildItem -Path (Join-Path $script:repoRoot 'src\WSUS\Public') -Filter '*.ps1' -File |
            ForEach-Object BaseName)
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'helpers\TestSetup.ps1')
    $script:manifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\WSUS\WSUS.psd1'
    $script:publicNames = @(Get-ChildItem -Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\WSUS\Public') -Filter '*.ps1' -File |
            ForEach-Object BaseName)
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'WSUS module contract' {
    It 'has a valid manifest' {
        { Test-ModuleManifest -Path $script:manifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'targets Windows PowerShell 5.1 (Desktop) with no RequiredModules' {
        $manifest = Import-PowerShellDataFile -Path $script:manifestPath
        $manifest.PowerShellVersion | Should -Be '5.1'
        $manifest.CompatiblePSEditions | Should -Be @('Desktop')
        $manifest.Keys | Should -Not -Contain 'RequiredModules'
    }

    It 'lists exactly the Public functions in FunctionsToExport' {
        $manifest = Import-PowerShellDataFile -Path $script:manifestPath
        @($manifest.FunctionsToExport | Sort-Object) | Should -Be @($script:publicNames | Sort-Object)
    }

    It 'exports exactly the Public functions when imported' {
        $exported = @((Get-Module -Name WSUS).ExportedFunctions.Keys | Sort-Object)
        $exported | Should -Be @($script:publicNames | Sort-Object)
    }

    Context 'help for <_>' -ForEach $script:publicNames {
        It 'has a synopsis, description and an example' {
            $help = Get-Help -Name $_ -Full
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Synopsis | Should -Not -BeLike "$_*" -Because 'a missing synopsis falls back to the syntax line'
            $help.Description | Should -Not -BeNullOrEmpty
            @($help.Examples.Example).Count | Should -BeGreaterThan 0
        }
    }
}
