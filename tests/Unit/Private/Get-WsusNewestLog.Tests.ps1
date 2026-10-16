BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Get-WsusNewestLog' {
    BeforeEach {
        $script:folder = Join-Path $TestDrive (New-Guid).Guid
        $null = New-Item -ItemType Directory -Path $script:folder -Force
        foreach ($name in 'maint_old.log', 'maint_new.log', 'decline_only.log') {
            $null = New-Item -Path (Join-Path $script:folder $name) -ItemType File
        }
        (Get-Item -Path (Join-Path $script:folder 'maint_old.log')).LastWriteTime = [datetime] '2026-01-01'
        (Get-Item -Path (Join-Path $script:folder 'maint_new.log')).LastWriteTime = [datetime] '2026-02-01'
    }

    It 'returns the newest log of the kind' {
        $log = InModuleScope WSUS -Parameters @{ Folder = $script:folder } { Get-WsusNewestLog -Kind Maintenance -Path $Folder }

        $log.Name | Should -Be 'maint_new.log'
    }

    It 'does not return a log of another kind' {
        $log = InModuleScope WSUS -Parameters @{ Folder = $script:folder } { Get-WsusNewestLog -Kind Decline -Path $Folder }

        $log.Name | Should -Be 'decline_only.log'
    }

    It 'returns nothing when the folder has no log of the kind' {
        $empty = Join-Path $TestDrive (New-Guid).Guid

        InModuleScope WSUS -Parameters @{ Folder = $empty } { Get-WsusNewestLog -Kind Maintenance -Path $Folder } |
            Should -BeNullOrEmpty
    }
}
