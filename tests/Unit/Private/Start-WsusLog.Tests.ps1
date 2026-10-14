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

    It 'creates the folder, starts a transcript named after the prefix and returns its path' {
        $folder = Join-Path $TestDrive 'logs\nested'

        $path = InModuleScope WSUS -Parameters @{ Folder = $folder } { Start-WsusLog -Prefix maint -Path $Folder }

        Test-Path -Path $folder -PathType Container | Should -BeTrue
        (Split-Path -Path $path -Leaf) | Should -Match '^maint_\d{8}_\d{4}\.log$'
        Split-Path -Path $path -Parent | Should -Be $folder
        Should -Invoke -ModuleName WSUS Start-Transcript -Times 1 -Exactly -ParameterFilter { $Path -eq $path }
    }
}
