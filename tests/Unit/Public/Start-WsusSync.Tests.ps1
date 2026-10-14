BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Start-WsusSync' {
    BeforeEach {
        $script:fake = New-FakeWsusServer -Name 'wsus01.contoso.local'
        Mock -ModuleName WSUS Get-WsusLocalFqdn { 'wsus01.contoso.local' }
        Mock -ModuleName WSUS Get-WsusServer { $script:fake }
        Mock -ModuleName WSUS Start-Sleep { }
        Mock -ModuleName WSUS Write-Progress { }
    }

    Context 'without -Wait' {
        It 'starts a full sync and returns a Started WSUS.SyncResult' {
            $result = Start-WsusSync

            $result.PSObject.TypeNames | Should -Contain 'WSUS.SyncResult'
            $result.Server | Should -Be 'wsus01.contoso.local'
            $result.Mode | Should -Be 'Full'
            $result.Status | Should -Be 'Started'
            $result.Started | Should -BeOfType ([datetime])
            $result.NextStep | Should -BeLike '*Get-WsusNodeStatus*'
            $script:fake.Calls | Should -Contain 'StartSynchronization'
        }

        It 'does not start a sync under -WhatIf' {
            Start-WsusSync -WhatIf
            $script:fake.Calls | Should -Not -Contain 'StartSynchronization'
        }

        It 'starts a full sync on a replica' {
            $script:fake = New-FakeWsusServer -IsReplica $true
            (Start-WsusSync).Mode | Should -Be 'Full'
            $script:fake.Calls | Should -Contain 'StartSynchronization'
        }
    }

    Context '-CategoryOnly' {
        It 'starts a category-only sync on an upstream' {
            $result = Start-WsusSync -CategoryOnly

            $result.Mode | Should -Be 'CategoryOnly'
            $script:fake.Calls | Should -Contain 'StartSynchronizationForCategoryOnly'
            $script:fake.Calls | Should -Not -Contain 'StartSynchronization'
        }

        It 'throws on a replica and starts nothing' {
            $script:fake = New-FakeWsusServer -IsReplica $true
            { Start-WsusSync -CategoryOnly } | Should -Throw '*Replica*'
            $script:fake.Calls | Should -Not -Contain 'StartSynchronizationForCategoryOnly'
        }
    }

    Context 'a sync is already running' {
        It 'warns and does not start another' {
            $script:fake = New-FakeWsusServer -SyncRunning
            $result = Start-WsusSync -WarningVariable warn -WarningAction SilentlyContinue

            $warn | Should -Not -BeNullOrEmpty
            $script:fake.Calls | Should -Not -Contain 'StartSynchronization'
            $result.Status | Should -Be 'AlreadyRunning'
        }

        It 'joins the running sync with -Wait' {
            $script:fake = New-FakeWsusServer -SyncRunning -SyncPolls 3
            $result = Start-WsusSync -Wait -WarningAction SilentlyContinue

            $script:fake.Calls | Should -Not -Contain 'StartSynchronization'
            $result.Status | Should -Be 'Finished'
        }
    }

    Context '-Wait' {
        It 'polls until the sync finishes and reports the last sync info' {
            $script:fake = New-FakeWsusServer -SyncPolls 3 -LastSyncResult 'Succeeded'
            $result = Start-WsusSync -Wait

            $result.Status | Should -Be 'Finished'
            $result.Result | Should -Be 'Succeeded'
            $result.Finished | Should -Be ([datetime] '2026-10-12T02:30:00')
            $result.Error | Should -BeNullOrEmpty
            Should -Invoke -ModuleName WSUS Write-Progress
        }

        It 'throws when the sync result is Failed' {
            $script:fake = New-FakeWsusServer -LastSyncResult 'Failed' -LastSyncError 'Cannot reach Microsoft'
            { Start-WsusSync -Wait } | Should -Throw '*Cannot reach Microsoft*'
        }

        It 'throws on timeout and says the sync keeps running' {
            $script:fake = New-FakeWsusServer -SyncPolls 1000
            { Start-WsusSync -Wait -TimeoutMinutes 1 } | Should -Throw '*keeps running*'
        }

        It 'defaults the timeout to 30 minutes category-only and 480 minutes full' {
            $script:fake = New-FakeWsusServer -SyncPolls 100
            { Start-WsusSync -Wait -CategoryOnly } | Should -Not -Throw
            $script:fake = New-FakeWsusServer -SyncPolls 121
            { Start-WsusSync -Wait -CategoryOnly } | Should -Throw '*30 minutes*'
            $script:fake = New-FakeWsusServer -SyncPolls 1000
            { Start-WsusSync -Wait } | Should -Not -Throw
        }

        It 'still polls under -Confirm:$false' {
            $script:fake = New-FakeWsusServer -SyncPolls 2
            (Start-WsusSync -Wait -Confirm:$false).Status | Should -Be 'Finished'
        }
    }
}
