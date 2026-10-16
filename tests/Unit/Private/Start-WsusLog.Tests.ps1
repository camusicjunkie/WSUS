BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Start-WsusLog' {
    BeforeEach {
        Mock -ModuleName WSUS Start-Transcript { }
    }

    It 'creates the folder, starts a transcript named after the kind and returns a log that remembers its settings' {
        $folder = Join-Path $TestDrive 'logs\nested'

        $log = InModuleScope WSUS -Parameters @{ Folder = $folder } { Start-WsusLog -Kind Maintenance -Path $Folder -Keep 7 }

        Test-Path -Path $folder -PathType Container | Should -BeTrue
        (Split-Path -Path $log.Transcript -Leaf) | Should -Match '^maint_\d{8}_\d{4}\.log$'
        Split-Path -Path $log.Transcript -Parent | Should -Be $folder
        $log.Prefix | Should -Be 'maint'
        $log.Path | Should -Be $folder
        $log.Keep | Should -Be 7
        Should -Invoke -ModuleName WSUS Start-Transcript -Times 1 -Exactly -ParameterFilter { $Path -eq $log.Transcript }
    }

    It 'names a decline log with the decline prefix' {
        $log = InModuleScope WSUS -Parameters @{ Folder = $TestDrive } { Start-WsusLog -Kind Decline -Path $Folder -Keep 96 }

        (Split-Path -Path $log.Transcript -Leaf) | Should -Match '^decline_\d{8}_\d{4}\.log$'
        $log.Prefix | Should -Be 'decline'
    }

    It 'uses the default log folder when -Path is not given' {
        Mock -ModuleName WSUS New-Item { }

        $log = InModuleScope WSUS { Start-WsusLog -Kind Maintenance -Keep 12 }

        $log.Path | Should -Be 'C:\ProgramData\WsusMaintenance'
        Should -Invoke -ModuleName WSUS New-Item -Times 1 -Exactly -ParameterFilter { $Path -eq 'C:\ProgramData\WsusMaintenance' }
    }

    It 'rejects a kind it does not know' {
        { InModuleScope WSUS { Start-WsusLog -Kind Other -Keep 1 } } | Should -Throw
    }
}
