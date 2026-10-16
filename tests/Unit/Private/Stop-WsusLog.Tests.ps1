BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Stop-WsusLog' {
    BeforeEach {
        Mock -ModuleName WSUS Start-Transcript { }
        Mock -ModuleName WSUS Stop-Transcript { }
        $script:folder = Join-Path $TestDrive (New-Guid).Guid
        $null = New-Item -ItemType Directory -Path $script:folder -Force
        foreach ($i in 1..5) {
            $maint = New-Item -Path (Join-Path $script:folder "maint_2026010$i.log") -ItemType File
            $maint.LastWriteTime = [datetime] "2026-01-0$i"
            $other = New-Item -Path (Join-Path $script:folder "decline_2026010$i.log") -ItemType File
            $other.LastWriteTime = [datetime] "2026-01-0$i"
        }
    }

    It 'keeps the newest logs of the log''s own kind, leaves other kinds alone and stops the transcript' {
        InModuleScope WSUS -Parameters @{ Folder = $script:folder } {
            $log = Start-WsusLog -Kind Maintenance -Path $Folder -Keep 2
            Stop-WsusLog -Log $log
        }

        (Get-ChildItem -Path $script:folder -Filter 'maint_*').Name | Sort-Object |
            Should -Be @('maint_20260104.log', 'maint_20260105.log')
        @(Get-ChildItem -Path $script:folder -Filter 'decline_*').Count | Should -Be 5
        Should -Invoke -ModuleName WSUS Stop-Transcript -Times 1 -Exactly
    }

    It 'applies the retention of a decline log to decline files only' {
        InModuleScope WSUS -Parameters @{ Folder = $script:folder } {
            $log = Start-WsusLog -Kind Decline -Path $Folder -Keep 3
            Stop-WsusLog -Log $log
        }

        @(Get-ChildItem -Path $script:folder -Filter 'decline_*').Count | Should -Be 3
        @(Get-ChildItem -Path $script:folder -Filter 'maint_*').Count | Should -Be 5
    }

    It 'still stops the transcript when the folder is gone' {
        InModuleScope WSUS -Parameters @{ Folder = $script:folder } {
            $log = Start-WsusLog -Kind Maintenance -Path $Folder -Keep 2
            Remove-Item -Path $Folder -Recurse -Force
            Stop-WsusLog -Log $log
        }

        Should -Invoke -ModuleName WSUS Stop-Transcript -Times 1 -Exactly
    }
}
