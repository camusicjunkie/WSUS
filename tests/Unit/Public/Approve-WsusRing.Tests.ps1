BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Approve-WsusRing' {
    BeforeEach {
        $script:fake = New-FakeWsusServer -Name 'wsus01.contoso.local'
        Mock -ModuleName WSUS Get-WsusLocalFqdn { 'wsus01.contoso.local' }
        Mock -ModuleName WSUS Get-WsusServer { $script:fake }
    }

    Context 'an update that passes the gate' {
        It 'approves it for every -To group and returns a WSUS.RingApproval row' {
            New-FakeWsusUpdate -Server $script:fake -Title 'KB1 Security Update' -Kb '5000001' -Installed 9 -NotInstalled 1 | Out-Null

            $row = Approve-WsusRing

            $row.PSObject.TypeNames | Should -Contain 'WSUS.RingApproval'
            $row.Update | Should -Be 'KB1 Security Update'
            $row.Kb | Should -Be '5000001'
            $row.Installed | Should -Be 9
            $row.Needed | Should -Be 10
            $row.Percent | Should -Be 90
            $row.Failed | Should -Be 0
            $row.Gate | Should -Be 'Passed'
            $row.Reason | Should -BeNullOrEmpty
            $row.ApprovedTo | Should -Be 'Workstations', 'Servers'
            $script:fake.Calls | Should -Contain 'Approve KB1 Security Update -> Workstations (Install)'
            $script:fake.Calls | Should -Contain 'Approve KB1 Security Update -> Servers (Install)'
        }
    }

    Context 'the gate holds an update' {
        It 'holds it while the soak is not finished' {
            New-FakeWsusUpdate -Server $script:fake -ApprovedFor @{ Pilot = (Get-Date).AddDays(-2) } | Out-Null

            $row = Approve-WsusRing -WarningAction SilentlyContinue

            $row.Gate | Should -Be 'Held'
            $row.Reason | Should -HaveCount 1
            $row.Reason[0] | Should -Match 'soak'
            $row.ApprovedTo | Should -BeNullOrEmpty
            $script:fake.Calls | Should -Not -Contain 'Approve Security Update for Windows (KB5000001) -> Servers (Install)'
            $script:fake.Calls -match '^Approve' | Should -BeNullOrEmpty
        }

        It 'honours -MinimumSoakDays' {
            New-FakeWsusUpdate -Server $script:fake -ApprovedFor @{ Pilot = (Get-Date).AddDays(-2) } | Out-Null

            (Approve-WsusRing -MinimumSoakDays 1).Gate | Should -Be 'Passed'
        }

        It 'holds it when no -From computer needed it' {
            New-FakeWsusUpdate -Server $script:fake -Installed 0 | Out-Null

            $row = Approve-WsusRing -WarningAction SilentlyContinue

            $row.Gate | Should -Be 'Held'
            $row.Needed | Should -Be 0
            $row.Percent | Should -Be 0
            $row.Reason -join ';' | Should -Match 'never tested'
        }

        It 'holds it when too few computers have it installed, flooring the percent' {
            New-FakeWsusUpdate -Server $script:fake -Installed 89 -NotInstalled 11 | Out-Null
            New-FakeWsusUpdate -Server $script:fake -Title 'Edge' -Installed 2 -NotInstalled 1 | Out-Null

            $rows = Approve-WsusRing -WarningAction SilentlyContinue

            $rows[0].Percent | Should -Be 89
            $rows[0].Gate | Should -Be 'Held'
            $rows[0].Reason -join ';' | Should -Match '89%'
            $rows[1].Percent | Should -Be 66
        }

        It 'counts installed-pending-reboot as installed' {
            New-FakeWsusUpdate -Server $script:fake -Installed 5 -InstalledPendingReboot 4 -NotInstalled 1 | Out-Null

            $row = Approve-WsusRing

            $row.Installed | Should -Be 9
            $row.Gate | Should -Be 'Passed'
        }

        It 'honours -MinimumInstalledPercent' {
            New-FakeWsusUpdate -Server $script:fake -Installed 5 -NotInstalled 5 | Out-Null

            (Approve-WsusRing -MinimumInstalledPercent 50).Gate | Should -Be 'Passed'
        }

        It 'holds it when any -From computer failed, and lists every reason' {
            New-FakeWsusUpdate -Server $script:fake -ApprovedFor @{ Pilot = (Get-Date).AddDays(-1) } -Installed 50 -Failed 1 | Out-Null

            $row = Approve-WsusRing -WarningAction SilentlyContinue

            $row.Gate | Should -Be 'Held'
            $row.Failed | Should -Be 1
            $row.Reason | Should -HaveCount 2
            $row.Reason -join ';' | Should -Match '1 failed'
        }
    }

    Context '-Force' {
        It 'approves a held update, shows Gate = Forced and keeps the reasons' {
            New-FakeWsusUpdate -Server $script:fake -ApprovedFor @{ Pilot = (Get-Date).AddDays(-1) } | Out-Null

            $row = Approve-WsusRing -Force

            $row.Gate | Should -Be 'Forced'
            $row.Reason | Should -Not -BeNullOrEmpty
            $row.ApprovedTo | Should -Be 'Workstations', 'Servers'
        }

        It 'leaves an update that passes as Passed' {
            New-FakeWsusUpdate -Server $script:fake | Out-Null

            (Approve-WsusRing -Force).Gate | Should -Be 'Passed'
        }
    }

    Context 'the end-of-run warning' {
        It 'writes one warning with the held count that names -Force and -WhatIf' {
            New-FakeWsusUpdate -Server $script:fake -Title 'A' -Installed 0 | Out-Null
            New-FakeWsusUpdate -Server $script:fake -Title 'B' -Installed 0 | Out-Null
            New-FakeWsusUpdate -Server $script:fake -Title 'C' | Out-Null

            Approve-WsusRing -WarningVariable warn -WarningAction SilentlyContinue | Out-Null

            @($warn) | Should -HaveCount 1
            "$($warn[0])" | Should -Match '2 update'
            "$($warn[0])" | Should -Match '-Force'
            "$($warn[0])" | Should -Match '-WhatIf'
        }

        It 'writes no warning when nothing was held' {
            New-FakeWsusUpdate -Server $script:fake | Out-Null

            Approve-WsusRing -WarningVariable warn | Out-Null

            @($warn) | Should -HaveCount 0
        }
    }

    Context 'which updates are candidates' {
        It 'skips declined and superseded updates' {
            New-FakeWsusUpdate -Server $script:fake -Title 'Declined' -IsDeclined $true | Out-Null
            New-FakeWsusUpdate -Server $script:fake -Title 'Old' -IsSuperseded $true | Out-Null

            Approve-WsusRing | Should -BeNullOrEmpty
            $script:fake.Calls -match '^Approve' | Should -BeNullOrEmpty
        }

        It 'approves only the -To groups that are missing the approval' {
            New-FakeWsusUpdate -Server $script:fake -ApprovedFor @{ Pilot = (Get-Date).AddDays(-10); Workstations = (Get-Date).AddDays(-3) } | Out-Null

            $row = Approve-WsusRing

            $row.ApprovedTo | Should -Be 'Servers'
            $script:fake.Calls -match '^Approve' | Should -HaveCount 1
        }

        It 'skips an update already approved for every -To group' {
            New-FakeWsusUpdate -Server $script:fake -ApprovedFor @{ Pilot = (Get-Date).AddDays(-10); Workstations = (Get-Date); Servers = (Get-Date) } | Out-Null

            Approve-WsusRing | Should -BeNullOrEmpty
        }

        It 'accepts the licence agreement before approving when one is required' {
            New-FakeWsusUpdate -Server $script:fake -Title 'Licensed' -RequiresLicense $true | Out-Null

            Approve-WsusRing | Out-Null

            $acts = @($script:fake.Calls -match '^(AcceptLicenseAgreement|Approve) ')
            $acts[0] | Should -Be 'AcceptLicenseAgreement Licensed'
            $acts[1] | Should -Match '^Approve Licensed'
        }

        It 'scopes the search to latest-revision Install approvals for -From and the chosen classifications' {
            New-FakeWsusUpdate -Server $script:fake | Out-Null

            Approve-WsusRing -Classification 'Security Updates' | Out-Null

            $scope = $script:fake.LastScope
            @($scope.ApprovedComputerTargetGroups.Name) | Should -Be 'Pilot'
            @($scope.Classifications.Title) | Should -Be 'Security Updates'
            "$($scope.ApprovedStates)" | Should -Be 'LatestRevisionApproved'
            "$($scope.UpdateApprovalActions)" | Should -Be 'Install'
        }

        It 'honours -From and -To' {
            $script:fake = New-FakeWsusServer -Groups 'Workstations', 'Servers'
            New-FakeWsusUpdate -Server $script:fake -ApprovedFor @{ Workstations = (Get-Date).AddDays(-10) } | Out-Null

            $row = Approve-WsusRing -From Workstations -To Servers

            $row.ApprovedTo | Should -Be 'Servers'
        }
    }

    Context 'ShouldProcess' {
        It 'with -WhatIf returns the full gate table and approves nothing' {
            New-FakeWsusUpdate -Server $script:fake -Title 'Good' | Out-Null
            New-FakeWsusUpdate -Server $script:fake -Title 'Bad' -Installed 0 | Out-Null

            $rows = Approve-WsusRing -WhatIf -WarningAction SilentlyContinue

            $rows.Gate | Should -Be 'Passed', 'Held'
            $rows[0].ApprovedTo | Should -BeNullOrEmpty
            $script:fake.Calls -match '^Approve' | Should -BeNullOrEmpty
        }

        It 'does not prompt by default (ConfirmImpact is Medium)' {
            (Get-Command Approve-WsusRing).ScriptBlock.Attributes.Where({ $_ -is [System.Management.Automation.CmdletBindingAttribute] }).ConfirmImpact |
                Should -Be 'Medium'
        }
    }

    Context 'connection and role' {
        It 'connects to the local FQDN on the standard SSL port by default' {
            Approve-WsusRing | Out-Null

            Should -Invoke -ModuleName WSUS Get-WsusServer -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'wsus01.contoso.local' -and $PortNumber -eq 8531 -and $UseSsl
            }
        }

        It 'works against a remote upstream with -WsusServer and -Port' {
            Approve-WsusRing -WsusServer 'wsus09.contoso.local' -Port 9999 | Out-Null

            Should -Invoke -ModuleName WSUS Get-WsusServer -Times 1 -ParameterFilter {
                $Name -eq 'wsus09.contoso.local' -and $PortNumber -eq 9999
            }
        }

        It 'refuses a replica and says to approve on the upstream, before changing anything' {
            $script:fake = New-FakeWsusServer -IsReplica $true
            New-FakeWsusUpdate -Server $script:fake | Out-Null

            { Approve-WsusRing } | Should -Throw '*replica*upstream*'
            $script:fake.Calls -match '^Approve' | Should -BeNullOrEmpty
        }

        It 'names the node and port when it cannot connect' {
            Mock -ModuleName WSUS Get-WsusServer { throw 'refused' }

            { Approve-WsusRing } | Should -Throw '*wsus01.contoso.local*8531*'
        }

        It 'throws before connecting when the UpdateServices module is missing' {
            Mock -ModuleName WSUS Get-Module { } -ParameterFilter { $ListAvailable }

            { Approve-WsusRing } | Should -Throw '*UpdateServices*'
            Should -Invoke -ModuleName WSUS Get-WsusServer -Times 0 -Exactly
        }
    }

    Context 'bad group or classification names' {
        It 'throws when -From does not exist, before approving anything' {
            { Approve-WsusRing -From 'Nope' } | Should -Throw "*'Nope'*"
        }

        It 'throws when a -To group does not exist' {
            New-FakeWsusUpdate -Server $script:fake | Out-Null

            { Approve-WsusRing -To 'Workstations', 'Nope' } | Should -Throw "*'Nope'*"
            $script:fake.Calls -match '^Approve' | Should -BeNullOrEmpty
        }

        It 'throws when none of the classifications exist' {
            { Approve-WsusRing -Classification 'Bogus' } | Should -Throw '*Bogus*'
        }
    }
}
