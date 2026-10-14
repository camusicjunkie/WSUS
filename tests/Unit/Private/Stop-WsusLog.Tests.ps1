BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Stop-WsusLog' {
    BeforeEach {
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

    It 'keeps the newest logs of its own prefix, leaves other prefixes alone and stops the transcript' {
        InModuleScope WSUS -Parameters @{ Folder = $script:folder } { Stop-WsusLog -Prefix maint -Path $Folder -Keep 2 }

        (Get-ChildItem -Path $script:folder -Filter 'maint_*').Name | Sort-Object |
            Should -Be @('maint_20260104.log', 'maint_20260105.log')
        @(Get-ChildItem -Path $script:folder -Filter 'decline_*').Count | Should -Be 5
        Should -Invoke -ModuleName WSUS Stop-Transcript -Times 1 -Exactly
    }

    It 'still stops the transcript when the folder is missing' {
        InModuleScope WSUS -Parameters @{ Folder = (Join-Path $TestDrive 'nothing') } {
            Stop-WsusLog -Prefix maint -Path $Folder -Keep 2
        }

        Should -Invoke -ModuleName WSUS Stop-Transcript -Times 1 -Exactly
    }
}
