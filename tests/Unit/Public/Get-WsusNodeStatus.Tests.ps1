BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Get-WsusNodeStatus' {
    BeforeEach {
        $script:fake = New-FakeWsusServer -Name 'wsus01.contoso.local' -ContentPath 'D:\WSUS' -LastSyncStart ([datetime] '2026-10-12T02:00:00')
        Mock -ModuleName WSUS Get-WsusLocalFqdn { 'wsus01.contoso.local' }
        Mock -ModuleName WSUS Get-WsusServer { $script:fake }
        Mock -ModuleName WSUS Get-PSDrive {
            [PSCustomObject] @{ Name = 'D'; Used = 75GB; Free = 25GB }
        }
        Mock -ModuleName WSUS Get-ChildItem {
            if ($Filter -eq 'maint_*.log') {
                [PSCustomObject] @{ FullName = 'C:\ProgramData\WsusMaintenance\maint_old.log'; LastWriteTime = [datetime] '2026-10-01' }
                [PSCustomObject] @{ FullName = 'C:\ProgramData\WsusMaintenance\maint_new.log'; LastWriteTime = [datetime] '2026-10-11' }
            }
            elseif ($Filter -eq 'decline_*.log') {
                [PSCustomObject] @{ FullName = 'C:\ProgramData\WsusMaintenance\decline_new.log'; LastWriteTime = [datetime] '2026-10-14' }
            }
        }
    }

    Context 'local upstream node' {
        It 'returns a WSUS.NodeStatus with role and last sync' {
            $result = Get-WsusNodeStatus

            $result.PSObject.TypeNames | Should -Contain 'WSUS.NodeStatus'
            $result.Server | Should -Be 'wsus01.contoso.local'
            $result.Role | Should -Be 'Upstream'
            $result.LastSyncTime | Should -Be ([datetime] '2026-10-12T02:00:00')
            $result.LastSyncResult | Should -Be 'Succeeded'
        }

        It 'reports content disk facts from the configured content path' {
            $result = Get-WsusNodeStatus

            $result.ContentPath | Should -Be 'D:\WSUS'
            $result.ContentFreeGB | Should -Be 25
            $result.ContentTotalGB | Should -Be 100
            $result.ContentFreePercent | Should -Be 25
        }

        It 'reports the newest maintenance and decline logs' {
            $result = Get-WsusNodeStatus

            $result.MaintenanceLogPath | Should -Be 'C:\ProgramData\WsusMaintenance\maint_new.log'
            $result.MaintenanceLogLastWriteTime | Should -Be ([datetime] '2026-10-11')
            $result.DeclineLogPath | Should -Be 'C:\ProgramData\WsusMaintenance\decline_new.log'
            $result.DeclineLogLastWriteTime | Should -Be ([datetime] '2026-10-14')
        }

        It 'leaves log facts empty when there are no logs' {
            Mock -ModuleName WSUS Get-ChildItem { }

            $result = Get-WsusNodeStatus

            $result.MaintenanceLogPath | Should -BeNullOrEmpty
            $result.DeclineLogPath | Should -BeNullOrEmpty
        }

        It 'connects to the local FQDN on the standard SSL port by default' {
            Get-WsusNodeStatus | Out-Null

            Should -Invoke -ModuleName WSUS Get-WsusServer -ParameterFilter {
                $Name -eq 'wsus01.contoso.local' -and $PortNumber -eq 8531 -and $UseSsl
            }
        }

        It 'honours -Port' {
            Get-WsusNodeStatus -Port 9999 | Out-Null

            Should -Invoke -ModuleName WSUS Get-WsusServer -ParameterFilter { $PortNumber -eq 9999 }
        }

        It 'does not change anything on the server' {
            Get-WsusNodeStatus | Out-Null

            $script:fake.Calls | Should -Not -Contain 'StartSynchronization'
        }
    }

    Context 'sync state and update counts' {
        It 'reports an idle node with no phase or progress' {
            $result = Get-WsusNodeStatus

            $result.SyncStatus | Should -Be 'NotProcessing'
            $result.SyncPhase | Should -BeNullOrEmpty
            $result.SyncProcessedItems | Should -BeNullOrEmpty
            $result.SyncTotalItems | Should -BeNullOrEmpty
        }

        It 'reports the phase and progress of a sync that is running' {
            $script:fake = New-FakeWsusServer -Name 'wsus01.contoso.local' -SyncRunning

            $result = Get-WsusNodeStatus

            $result.SyncStatus | Should -Be 'Running'
            $result.SyncPhase | Should -Be 'Updates'
            $result.SyncProcessedItems | Should -Be 5
            $result.SyncTotalItems | Should -Be 10
        }

        It 'reports the error code when the last sync failed' {
            $script:fake = New-FakeWsusServer -Name 'wsus01.contoso.local' -LastSyncResult 'Failed' -LastSyncError 'UssInternalError'

            $result = Get-WsusNodeStatus

            $result.LastSyncResult | Should -Be 'Failed'
            $result.LastSyncError | Should -Be 'UssInternalError'
        }

        It 'leaves the error empty when the last sync succeeded' {
            (Get-WsusNodeStatus).LastSyncError | Should -BeNullOrEmpty
        }

        It 'reports the update, approved and declined counts' {
            $script:fake.Status.UpdateCount = 343
            $script:fake.Status.ApprovedUpdateCount = 12
            $script:fake.Status.DeclinedUpdateCount = 331

            $result = Get-WsusNodeStatus

            $result.UpdateCount | Should -Be 343
            $result.ApprovedUpdateCount | Should -Be 12
            $result.DeclinedUpdateCount | Should -Be 331
        }

        It 'reports content still to download and failed downloads' {
            $script:fake.Download.TotalBytesToDownload = 300MB
            $script:fake.Download.DownloadedBytes = 100MB
            $script:fake.Download.FailedCount = 2

            $result = Get-WsusNodeStatus

            $result.DownloadPendingMB | Should -Be 200
            $result.DownloadFailedCount | Should -Be 2
        }

        It 'reports no pending download when content is complete' {
            $script:fake.Download.TotalBytesToDownload = 300MB
            $script:fake.Download.DownloadedBytes = 300MB

            (Get-WsusNodeStatus).DownloadPendingMB | Should -Be 0
        }

        It 'reports the sync and count facts for a remote node too' {
            $script:fake = New-FakeWsusServer -Name 'wsus02.contoso.local' -IsReplica $true -SyncRunning
            $script:fake.Status.UpdateCount = 250

            $result = Get-WsusNodeStatus -WsusServer 'wsus02.contoso.local'

            $result.SyncStatus | Should -Be 'Running'
            $result.UpdateCount | Should -Be 250
        }
    }

    Context 'replica role' {
        It 'reports Replica' {
            $script:fake.Config.IsReplicaServer = $true

            (Get-WsusNodeStatus).Role | Should -Be 'Replica'
        }
    }

    Context 'a node that has never synced' {
        It 'leaves the last sync facts empty' {
            $script:fake = New-FakeWsusServer -LastSyncStart $null

            $result = Get-WsusNodeStatus

            $result.LastSyncTime | Should -BeNullOrEmpty
            $result.LastSyncResult | Should -BeNullOrEmpty
        }
    }

    Context 'remote node' {
        It 'reports role and last sync but no disk or log facts' {
            $script:fake = New-FakeWsusServer -Name 'wsus02.contoso.local' -IsReplica $true

            $result = Get-WsusNodeStatus -WsusServer 'wsus02.contoso.local'

            $result.Role | Should -Be 'Replica'
            $result.LastSyncResult | Should -Be 'Succeeded'
            $result.ContentPath | Should -BeNullOrEmpty
            $result.ContentFreeGB | Should -BeNullOrEmpty
            $result.ContentFreePercent | Should -BeNullOrEmpty
            $result.MaintenanceLogPath | Should -BeNullOrEmpty
            $result.DeclineLogPath | Should -BeNullOrEmpty
            Should -Invoke -ModuleName WSUS Get-PSDrive -Times 0 -Exactly
            Should -Invoke -ModuleName WSUS Get-ChildItem -Times 0 -Exactly
        }
    }

    Context 'many servers through the pipeline' {
        It 'returns one object per server' {
            $result = 'wsus01.contoso.local', 'wsus02.contoso.local' | Get-WsusNodeStatus

            @($result).Count | Should -Be 2
            $result.Server | Should -Be 'wsus01.contoso.local', 'wsus02.contoso.local'
        }

        It 'accepts objects with a WsusServer property' {
            $result = [PSCustomObject] @{ WsusServer = 'wsus02.contoso.local' } | Get-WsusNodeStatus

            $result.Server | Should -Be 'wsus02.contoso.local'
        }

        It 'writes a non-terminating error naming node and port for an unreachable node and carries on' {
            Mock -ModuleName WSUS Get-WsusServer { throw 'connection refused' } -ParameterFilter { $Name -eq 'bad.contoso.local' }

            $result = 'bad.contoso.local', 'wsus01.contoso.local' | Get-WsusNodeStatus -ErrorVariable err -ErrorAction SilentlyContinue

            @($result).Count | Should -Be 1
            $result.Server | Should -Be 'wsus01.contoso.local'
            $unreachable = @($err | Where-Object { $_.FullyQualifiedErrorId -like 'WsusNodeUnreachable*' })
            $unreachable.Count | Should -Be 1
            "$($unreachable[0])" | Should -Match 'bad\.contoso\.local'
            "$($unreachable[0])" | Should -Match '8531'
        }
    }

    Context 'prerequisites' {
        It 'throws before connecting when the UpdateServices module is missing' {
            Mock -ModuleName WSUS Get-Module { } -ParameterFilter { $ListAvailable }

            { Get-WsusNodeStatus } | Should -Throw '*UpdateServices*'
            Should -Invoke -ModuleName WSUS Get-WsusServer -Times 0 -Exactly
        }
    }
}
