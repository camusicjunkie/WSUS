BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'ConvertTo-WsusUpstream' {
    BeforeEach {
        $script:fake = New-FakeWsusServer -Name 'wsus02.contoso.local' -IsReplica $true -UpstreamName 'wsus01.contoso.local'
        Mock -ModuleName WSUS Get-WsusLocalFqdn { 'wsus02.contoso.local' }
        Mock -ModuleName WSUS Get-WsusServer { $script:fake }
        Mock -ModuleName WSUS Test-WsusElevated { $true }
        Mock -ModuleName WSUS Test-WsusUpstreamReachable { $false }
    }

    It 'turns a replica into an upstream that syncs from Microsoft and returns a PromoteResult' {
        $result = ConvertTo-WsusUpstream -Confirm:$false

        $config = $script:fake.Config
        $config.IsReplicaServer | Should -BeFalse
        $config.SyncFromMicrosoftUpdate | Should -BeTrue
        $config.GetContentFromMU | Should -BeTrue
        $config.UpstreamWsusServerName | Should -BeNullOrEmpty
        $config.UpstreamWsusServerPortNumber | Should -Be 0
        $script:fake.Calls | Should -Contain 'Config.Save'

        $result.PSObject.TypeNames | Should -Contain 'WSUS.PromoteResult'
        $result.Server | Should -Be 'wsus02.contoso.local'
        $result.PreviousUpstream | Should -Be 'wsus01.contoso.local:8531'
        $result.Role | Should -Be 'Upstream'
        $result.NextStep | Should -BeLike '*Set-WsusUpstreamConfig*Set-WsusReplicaConfig -UpstreamFqdn*'
    }

    It 'throws and changes nothing when the node is already an Upstream' {
        $script:fake = New-FakeWsusServer -Name 'wsus01.contoso.local' -IsReplica $false

        { ConvertTo-WsusUpstream -Confirm:$false } | Should -Throw '*Set-WsusUpstreamConfig*'
        $script:fake.Calls | Should -Not -Contain 'Config.Save'
    }

    It 'refuses when the configured upstream still answers' {
        Mock -ModuleName WSUS Test-WsusUpstreamReachable { $true }

        { ConvertTo-WsusUpstream -Confirm:$false } | Should -Throw '*-Force*'
        $script:fake.Config.IsReplicaServer | Should -BeTrue
        $script:fake.Calls | Should -Not -Contain 'Config.Save'
    }

    It 'promotes a reachable upstream when -Force is given' {
        Mock -ModuleName WSUS Test-WsusUpstreamReachable { $true }

        ConvertTo-WsusUpstream -Force -Confirm:$false | Out-Null

        $script:fake.Config.IsReplicaServer | Should -BeFalse
        Should -Invoke -ModuleName WSUS Test-WsusUpstreamReachable -Times 0
    }

    It 'changes nothing and skips the probe under -WhatIf' {
        Mock -ModuleName WSUS Test-WsusUpstreamReachable { $true }

        ConvertTo-WsusUpstream -WhatIf | Out-Null

        $script:fake.Config.IsReplicaServer | Should -BeTrue
        $script:fake.Calls | Should -Not -Contain 'Config.Save'
        Should -Invoke -ModuleName WSUS Test-WsusUpstreamReachable -Times 0
    }
}
