BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Set-WsusSyncSource' {
    Context 'Microsoft Update as the sync source' {
        BeforeAll {
            $script:fake = New-FakeWsusServer -IsReplica $true -UpstreamName 'wsus01.contoso.local'
            $script:config = $script:fake.GetConfiguration()
            InModuleScope WSUS -Parameters @{ Config = $script:config } {
                param ($Config)
                Set-WsusSyncSource -Config $Config -MicrosoftUpdate
            }
        }

        It 'turns replica mode off and syncs from Microsoft Update' {
            $script:config.IsReplicaServer | Should -BeFalse
            $script:config.SyncFromMicrosoftUpdate | Should -BeTrue
        }

        It 'clears the upstream and downloads content from Microsoft Update' {
            $script:config.UpstreamWsusServerName | Should -Be ''
            $script:config.UpstreamWsusServerPortNumber | Should -Be 0
            $script:config.GetContentFromMU | Should -BeTrue
        }

        It 'sets the content flags' {
            $script:config.DownloadExpressPackages | Should -BeFalse
            $script:config.HostBinariesOnMicrosoftUpdate | Should -BeFalse
            $script:config.DownloadUpdateBinariesAsNeeded | Should -BeTrue
            $script:config.TargetingMode | Should -Be 'Client'
        }

        It 'leaves saving to the caller' {
            $script:fake.Calls | Should -Not -Contain 'Config.Save'
        }
    }

    Context 'an Upstream as the sync source' {
        BeforeAll {
            $script:fake = New-FakeWsusServer
            $script:config = $script:fake.GetConfiguration()
            $script:config.UseProxy = $true
            InModuleScope WSUS -Parameters @{ Config = $script:config } {
                param ($Config)
                Set-WsusSyncSource -Config $Config -UpstreamFqdn 'wsus01.contoso.local' -UpstreamPort 8531
            }
        }

        It 'makes the node a replica of the upstream' {
            $script:config.IsReplicaServer | Should -BeTrue
            $script:config.SyncFromMicrosoftUpdate | Should -BeFalse
            $script:config.UpstreamWsusServerName | Should -Be 'wsus01.contoso.local'
            $script:config.UpstreamWsusServerPortNumber | Should -Be 8531
        }

        It 'takes content from the upstream and does not use a proxy' {
            $script:config.GetContentFromMU | Should -BeFalse
            $script:config.UseProxy | Should -BeFalse
        }

        It 'sets the content flags' {
            $script:config.DownloadExpressPackages | Should -BeFalse
            $script:config.HostBinariesOnMicrosoftUpdate | Should -BeFalse
            $script:config.DownloadUpdateBinariesAsNeeded | Should -BeTrue
            $script:config.TargetingMode | Should -Be 'Client'
        }

        It 'uses SSL on 8531 and no SSL on any other port' {
            $script:config.UpstreamWsusServerUseSsl | Should -BeTrue
            InModuleScope WSUS -Parameters @{ Config = $script:config } {
                param ($Config)
                Set-WsusSyncSource -Config $Config -UpstreamFqdn 'wsus01.contoso.local' -UpstreamPort 8530
            }
            $script:config.UpstreamWsusServerUseSsl | Should -BeFalse
            $script:config.UpstreamWsusServerPortNumber | Should -Be 8530
        }

        It 'defaults to port 8531' {
            InModuleScope WSUS -Parameters @{ Config = $script:config } {
                param ($Config)
                Set-WsusSyncSource -Config $Config -UpstreamFqdn 'wsus01.contoso.local'
            }
            $script:config.UpstreamWsusServerPortNumber | Should -Be 8531
        }

        It 'leaves saving to the caller' {
            $script:fake.Calls | Should -Not -Contain 'Config.Save'
        }
    }

    Context 'the order WSUS requires' {
        BeforeAll {
            # WSUS refuses SyncFromMicrosoftUpdate = true while IsReplicaServer is true.
            $script:strict = [PSCustomObject] @{
                Replica = $true; Sync = $false
                UpstreamWsusServerName = 'wsus01.contoso.local'; UpstreamWsusServerPortNumber = 8531; UpstreamWsusServerUseSsl = $true
                GetContentFromMU = $false; UseProxy = $false; DownloadExpressPackages = $true
                HostBinariesOnMicrosoftUpdate = $true; DownloadUpdateBinariesAsNeeded = $false; TargetingMode = 'Server'
            }
            $script:strict | Add-Member -MemberType ScriptProperty -Name IsReplicaServer -Value { $this.Replica } -SecondValue {
                param ($value) $this.Replica = $value
            }
            $script:strict | Add-Member -MemberType ScriptProperty -Name SyncFromMicrosoftUpdate -Value { $this.Sync } -SecondValue {
                param ($value)
                if ($value -and $this.Replica) { throw 'Cannot sync from Microsoft Update while the server is a replica.' }
                $this.Sync = $value
            }
        }

        It 'turns replica mode off before it syncs from Microsoft Update' {
            { InModuleScope WSUS -Parameters @{ Config = $script:strict } {
                    param ($Config)
                    Set-WsusSyncSource -Config $Config -MicrosoftUpdate
                } } | Should -Not -Throw
            $script:strict.SyncFromMicrosoftUpdate | Should -BeTrue
        }
    }
}

Describe 'Set-WsusSyncSchedule' {
    BeforeAll {
        $script:fake = New-FakeWsusServer
        $script:subscription = $script:fake.GetSubscription()
        InModuleScope WSUS -Parameters @{ Subscription = $script:subscription } {
            param ($Subscription)
            Set-WsusSyncSchedule -Subscription $Subscription -SyncsPerDay 4 -FirstSyncUtcHour 3
        }
    }

    It 'turns automatic sync on with the first sync hour and the daily count' {
        $script:subscription.SynchronizeAutomatically | Should -BeTrue
        $script:subscription.SynchronizeAutomaticallyTimeOfDay | Should -Be ([timespan]::FromHours(3))
        $script:subscription.NumberOfSynchronizationsPerDay | Should -Be 4
    }

    It 'leaves saving to the caller' {
        $script:fake.Calls | Should -Not -Contain 'Subscription.Save'
    }

    It 'rejects values outside the range WSUS accepts' {
        { InModuleScope WSUS -Parameters @{ Subscription = $script:subscription } {
                param ($Subscription)
                Set-WsusSyncSchedule -Subscription $Subscription -SyncsPerDay 25 -FirstSyncUtcHour 3
            } } | Should -Throw
        { InModuleScope WSUS -Parameters @{ Subscription = $script:subscription } {
                param ($Subscription)
                Set-WsusSyncSchedule -Subscription $Subscription -SyncsPerDay 2 -FirstSyncUtcHour 24
            } } | Should -Throw
    }
}
