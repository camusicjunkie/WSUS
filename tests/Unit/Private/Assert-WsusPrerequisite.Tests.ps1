BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

# Foundation helper with decisions of its own (a single error listing everything missing), tested
# directly because the public functions that use -Administrator and -Feature arrive in later slices.
Describe 'Assert-WsusPrerequisite' {
    It 'returns nothing when everything is present' {
        Mock -ModuleName WSUS Test-WsusElevated { $true }
        Mock -ModuleName WSUS Get-WindowsFeature { [PSCustomObject] @{ InstallState = 'Available' } }

        InModuleScope WSUS {
            Assert-WsusPrerequisite -Module UpdateServices -Administrator -Feature UpdateServices
        } | Should -BeNullOrEmpty
    }

    It 'reports every missing prerequisite in one error' {
        Mock -ModuleName WSUS Test-WsusElevated { $false }
        Mock -ModuleName WSUS Get-WindowsFeature { }

        $thrown = $null
        try {
            InModuleScope WSUS {
                Assert-WsusPrerequisite -Module NoSuchModule, UpdateServices -Administrator -Feature UpdateServices
            }
        }
        catch { $thrown = $_.Exception.Message }

        $thrown | Should -Match 'NoSuchModule'
        $thrown | Should -Match 'elevated'
        $thrown | Should -Match "feature 'UpdateServices'"
        $thrown | Should -Not -Match "module 'UpdateServices'"
    }

    It 'treats a feature that is not available as missing' {
        Mock -ModuleName WSUS Get-WindowsFeature { [PSCustomObject] @{ InstallState = 'Removed' } }

        { InModuleScope WSUS { Assert-WsusPrerequisite -Feature UpdateServices } } | Should -Throw '*UpdateServices*'
    }
}
