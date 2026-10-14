BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Invoke-WsusMaintenance' {
    BeforeEach {
        $now = [datetime]::UtcNow
        $script:fake = New-FakeWsusServer -Updates @(
            @{ Title = 'Preview of Windows 11 (KB1)'; Kb = '1' },
            @{ Title = 'Old superseded update (KB2)'; Kb = '2'; IsSuperseded = $true; ArrivalDate = $now.AddDays(-60) },
            @{ Title = 'Recent superseded update (KB3)'; Kb = '3'; IsSuperseded = $true; ArrivalDate = $now.AddDays(-5) },
            @{ Title = 'Current update (KB4)'; Kb = '4' }
        )
        Mock -ModuleName WSUS Get-WsusLocalFqdn { 'wsus01.contoso.local' }
        Mock -ModuleName WSUS Test-WsusElevated { $true }
        Mock -ModuleName WSUS Get-WsusServer { $script:fake }
        # Real Start-/Stop-WsusLog run (retention is asserted on files); only the transcript and folder creation are faked.
        Mock -ModuleName WSUS Start-Transcript { }
        Mock -ModuleName WSUS Stop-Transcript { }
        Mock -ModuleName WSUS New-Item { }
        Mock -ModuleName WSUS Invoke-WsusServerCleanup { [PSCustomObject]@{ DiskSpaceFreed = 123 } }
        Mock -ModuleName WSUS Invoke-WsusDatabaseQuery { }
    }

    It 'on an upstream declines, cleans up, reindexes and returns a WSUS.MaintenanceRun' {
        $result = Invoke-WsusMaintenance

        $result.PSObject.TypeNames | Should -Contain 'WSUS.MaintenanceRun'
        $result.Server | Should -Be 'wsus01.contoso.local'
        $result.Role | Should -Be 'Upstream'
        $result.Declined | Should -Be 2
        $result.DeclinedUpdates | Should -Be @('Preview of Windows 11 (KB1)', 'Old superseded update (KB2)')
        $result.Cleanup.DiskSpaceFreed | Should -Be 123
        $result.Database | Should -Be 'Completed'
        $result.Log | Should -Match ('^' + [regex]::Escape('C:\ProgramData\WsusMaintenance\') + 'maint_\d{8}_\d{4}\.log$')
        $script:fake.Calls | Should -Not -Contain 'Update.Decline:Recent superseded update (KB3)'
        Should -Invoke -ModuleName WSUS Invoke-WsusServerCleanup -Times 1 -Exactly -ParameterFilter {
            $DeclineExpiredUpdates -and $DeclineSupersededUpdates -and $CleanupObsoleteUpdates -and $CompressUpdates
        }
        Should -Invoke -ModuleName WSUS Invoke-WsusDatabaseQuery -Times 1 -Exactly -ParameterFilter {
            $Instance -eq '\.\pipe\MICROSOFT##WID\tsql\query' -and $Query -like '*sp_updatestats*'
        }
    }

    It 'refuses a -WsusServer that is not this node, before logging or connecting' {
        { Invoke-WsusMaintenance -WsusServer 'wsus09.contoso.local' } | Should -Throw "*local*wsus09.contoso.local*"
        Should -Invoke -ModuleName WSUS Start-Transcript -Times 0 -Exactly
        Should -Invoke -ModuleName WSUS Get-WsusServer -Times 0 -Exactly
    }

    It 'accepts the local FQDN in any case' {
        { Invoke-WsusMaintenance -WsusServer 'WSUS01.contoso.local' } | Should -Not -Throw
    }

    It 'on a replica skips declines and uses the cleanup options without decline options' {
        $script:fake = New-FakeWsusServer -IsReplica $true

        $result = Invoke-WsusMaintenance

        $result.Role | Should -Be 'Replica'
        $result.Declined | Should -Be 0
        $result.Database | Should -Be 'Completed'
        $script:fake.Calls | Should -Not -Contain 'GetUpdates'
        Should -Invoke -ModuleName WSUS Invoke-WsusServerCleanup -Times 1 -Exactly -ParameterFilter {
            -not $DeclineExpiredUpdates -and -not $DeclineSupersededUpdates -and $CleanupUnneededContentFiles
        }
    }

    It '-SupersededAgeDays 0 also declines recently superseded updates' {
        $result = Invoke-WsusMaintenance -SupersededAgeDays 0

        $result.DeclinedUpdates | Should -Contain 'Recent superseded update (KB3)'
    }

    It 'uses -DeclinePattern instead of the default' {
        $result = Invoke-WsusMaintenance -DeclinePattern 'KB4' -SupersededAgeDays 365

        $result.DeclinedUpdates | Should -Be @('Current update (KB4)')
    }

    It 'passes -WidInstance to the database query' {
        $null = Invoke-WsusMaintenance -WidInstance '\.\pipe\other'

        Should -Invoke -ModuleName WSUS Invoke-WsusDatabaseQuery -Times 1 -Exactly -ParameterFilter { $Instance -eq '\.\pipe\other' }
    }

    It 'does nothing under -WhatIf and reports the database and cleanup as skipped' {
        $result = Invoke-WsusMaintenance -WhatIf

        $result.Declined | Should -Be 0
        $result.Cleanup | Should -BeNullOrEmpty
        $result.Database | Should -Be 'Skipped'
        Should -Invoke -ModuleName WSUS Invoke-WsusServerCleanup -Times 0 -Exactly
        Should -Invoke -ModuleName WSUS Invoke-WsusDatabaseQuery -Times 0 -Exactly
    }

    It 'logs to -LogPath with the maint prefix and keeps the newest 12 maint logs by default' {
        1..15 | ForEach-Object {
            (New-Item -ItemType File -Path (Join-Path $TestDrive ('maint_20260101_{0:00}00.log' -f $_)) -Force).LastWriteTime = [datetime] '2026-01-01' + [timespan]::FromHours($_)
        }
        1..3 | ForEach-Object { New-Item -ItemType File -Path (Join-Path $TestDrive ('decline_20260101_{0:00}00.log' -f $_)) -Force | Out-Null }

        $result = Invoke-WsusMaintenance -LogPath $TestDrive

        $result.Log | Should -BeLike (Join-Path $TestDrive 'maint_*.log')
        @(Get-ChildItem -Path $TestDrive -Filter 'maint_*.log').Count | Should -Be 12
        @(Get-ChildItem -Path $TestDrive -Filter 'decline_*.log').Count | Should -Be 3
    }

    It 'throws at the first failure, skips later steps and still applies log retention' {
        1..15 | ForEach-Object {
            (New-Item -ItemType File -Path (Join-Path $TestDrive ('maint_20260101_{0:00}00.log' -f $_)) -Force).LastWriteTime = [datetime] '2026-01-01' + [timespan]::FromHours($_)
        }
        Mock -ModuleName WSUS Invoke-WsusServerCleanup { throw 'cleanup blew up' }

        { Invoke-WsusMaintenance -LogPath $TestDrive } | Should -Throw '*cleanup blew up*'
        Should -Invoke -ModuleName WSUS Invoke-WsusDatabaseQuery -Times 0 -Exactly
        @(Get-ChildItem -Path $TestDrive -Filter 'maint_*.log').Count | Should -Be 12
    }

    It 'throws when not elevated' {
        Mock -ModuleName WSUS Test-WsusElevated { $false }

        { Invoke-WsusMaintenance } | Should -Throw '*elevated*'
    }
}
