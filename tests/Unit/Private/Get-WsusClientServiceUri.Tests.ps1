BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Get-WsusClientServiceUri' {
    It 'uses https on the SSL port 8531' {
        InModuleScope WSUS { Get-WsusClientServiceUri -Fqdn 'wsus01.contoso.local' -Port 8531 } |
            Should -Be 'https://wsus01.contoso.local:8531/ClientWebService/client.asmx'
    }

    It 'uses http on any other port' {
        InModuleScope WSUS { Get-WsusClientServiceUri -Fqdn 'wsus01.contoso.local' -Port 8530 } |
            Should -Be 'http://wsus01.contoso.local:8530/ClientWebService/client.asmx'
    }

    It 'defaults to the SSL port' {
        InModuleScope WSUS { Get-WsusClientServiceUri -Fqdn 'wsus01.contoso.local' } |
            Should -Match '^https://.*:8531/'
    }
}

Describe 'Connect-WsusNode protocol' {
    BeforeAll {
        Mock -ModuleName WSUS Get-WsusServer { }
    }

    It 'passes -UseSsl on 8531' {
        InModuleScope WSUS { Connect-WsusNode -Server 'wsus01.contoso.local' -Port 8531 }
        Should -Invoke -ModuleName WSUS Get-WsusServer -Times 1 -Exactly -ParameterFilter { $UseSsl }
    }

    It 'does not pass -UseSsl on 8530' {
        InModuleScope WSUS { Connect-WsusNode -Server 'wsus01.contoso.local' -Port 8530 }
        Should -Invoke -ModuleName WSUS Get-WsusServer -Times 1 -Exactly -ParameterFilter { $PortNumber -eq 8530 -and -not $UseSsl }
    }
}
