BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
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
