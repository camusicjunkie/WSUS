BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Assert-WsusRole' {
    Context '-Role Upstream' {
        It 'returns nothing on an Upstream' {
            $fake = New-FakeWsusServer -IsReplica $false

            InModuleScope WSUS -Parameters @{ Wsus = $fake } { Assert-WsusRole -Wsus $Wsus -Role Upstream } |
                Should -BeNullOrEmpty
        }

        It 'throws on a Replica, naming the node' {
            $fake = New-FakeWsusServer -Name 'wsus02.contoso.local' -IsReplica $true

            { InModuleScope WSUS -Parameters @{ Wsus = $fake } { Assert-WsusRole -Wsus $Wsus -Role Upstream } } |
                Should -Throw "*'wsus02.contoso.local' is a Replica; this action runs on an Upstream only.*"
        }

        It 'appends -Instead to the error' {
            $fake = New-FakeWsusServer -IsReplica $true

            { InModuleScope WSUS -Parameters @{ Wsus = $fake } { Assert-WsusRole -Wsus $Wsus -Role Upstream -Instead 'Promote it first.' } } |
                Should -Throw '*only. Promote it first.'
        }
    }

    Context '-Role Replica' {
        It 'returns nothing on a Replica' {
            $fake = New-FakeWsusServer -IsReplica $true

            InModuleScope WSUS -Parameters @{ Wsus = $fake } { Assert-WsusRole -Wsus $Wsus -Role Replica } |
                Should -BeNullOrEmpty
        }

        It 'throws on an Upstream, naming the node and Set-WsusUpstreamConfig by default' {
            $fake = New-FakeWsusServer -Name 'wsus01.contoso.local' -IsReplica $false

            { InModuleScope WSUS -Parameters @{ Wsus = $fake } { Assert-WsusRole -Wsus $Wsus -Role Replica } } |
                Should -Throw "*'wsus01.contoso.local' is an Upstream, not a Replica. Use Set-WsusUpstreamConfig instead."
        }

        It 'names the function given in -Instead' {
            $fake = New-FakeWsusServer -IsReplica $false

            { InModuleScope WSUS -Parameters @{ Wsus = $fake } { Assert-WsusRole -Wsus $Wsus -Role Replica -Instead 'Other-Function' } } |
                Should -Throw '*Use Other-Function instead.'
        }
    }

    It 'requires a role it knows' {
        $fake = New-FakeWsusServer

        { InModuleScope WSUS -Parameters @{ Wsus = $fake } { Assert-WsusRole -Wsus $Wsus -Role Other } } | Should -Throw
    }
}
