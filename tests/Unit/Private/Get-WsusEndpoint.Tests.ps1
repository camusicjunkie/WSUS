BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Get-WsusEndpoint' {
    It 'uses SSL and https on the SSL port 8531' {
        $endpoint = InModuleScope WSUS { Get-WsusEndpoint -Fqdn 'wsus01.contoso.local' -Port 8531 }
        $endpoint.UseSsl | Should -BeTrue
        $endpoint.ClientServiceUri | Should -Be 'https://wsus01.contoso.local:8531/ClientWebService/client.asmx'
    }

    It 'uses no SSL and http on any other port' {
        $endpoint = InModuleScope WSUS { Get-WsusEndpoint -Fqdn 'wsus01.contoso.local' -Port 8530 }
        $endpoint.UseSsl | Should -BeFalse
        $endpoint.ClientServiceUri | Should -Be 'http://wsus01.contoso.local:8530/ClientWebService/client.asmx'
    }

    It 'defaults to the SSL port' {
        $endpoint = InModuleScope WSUS { Get-WsusEndpoint -Fqdn 'wsus01.contoso.local' }
        $endpoint.Port | Should -Be 8531
        $endpoint.UseSsl | Should -BeTrue
    }

    It 'returns the name and port it was given' {
        $endpoint = InModuleScope WSUS { Get-WsusEndpoint -Fqdn 'wsus02.contoso.local' -Port 8530 }
        $endpoint.Fqdn | Should -Be 'wsus02.contoso.local'
        $endpoint.Port | Should -Be 8530
    }
}
