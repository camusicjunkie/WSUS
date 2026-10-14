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
