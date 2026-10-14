BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

# Private helper with decisions of its own (every problem listed in one error). Set-WsusNodeConfig
# tests mock it, so the rules are tested here with fake certificate objects.
Describe 'Test-WsusCertificate' {
    BeforeAll {
        function New-FakeCert {
            param (
                [bool] $HasPrivateKey = $true,
                [datetime] $NotAfter = (Get-Date).AddDays(365),
                [string[]] $Eku = '1.3.6.1.5.5.7.3.1',
                [string[]] $San = @('wsus.contoso.local', 'wsus01.contoso.local')
            )
            [PSCustomObject] @{
                HasPrivateKey        = $HasPrivateKey
                NotAfter             = $NotAfter
                EnhancedKeyUsageList = @($Eku | ForEach-Object { [PSCustomObject] @{ ObjectId = $_ } })
                DnsNameList          = @($San | ForEach-Object { [PSCustomObject] @{ Unicode = $_ } })
            }
        }
        $script:thumb = 'A' * 40
        $script:names = 'wsus.contoso.local', 'wsus01.contoso.local'
    }

    It 'accepts a valid certificate' {
        Mock -ModuleName WSUS Get-Item { New-FakeCert }

        { InModuleScope WSUS -Parameters @{ T = $script:thumb; N = $script:names } {
            Test-WsusCertificate -Thumbprint $T -RequiredName $N
        } } | Should -Not -Throw
    }

    It 'throws when the certificate is not in the machine store' {
        Mock -ModuleName WSUS Get-Item { }

        { InModuleScope WSUS -Parameters @{ T = $script:thumb; N = $script:names } {
            Test-WsusCertificate -Thumbprint $T -RequiredName $N
        } } | Should -Throw '*is not in Cert:\LocalMachine\My*'
    }

    It 'lists every problem in one error' {
        Mock -ModuleName WSUS Get-Item {
            New-FakeCert -HasPrivateKey $false -NotAfter (Get-Date).AddDays(10) -Eku '1.3.6.1.5.5.7.3.2' -San 'wsus.contoso.local'
        }

        $thrown = $null
        try {
            InModuleScope WSUS -Parameters @{ T = $script:thumb; N = $script:names } {
                Test-WsusCertificate -Thumbprint $T -RequiredName $N
            }
        }
        catch { $thrown = $_.Exception.Message }

        $thrown | Should -Match 'no private key'
        $thrown | Should -Match 'expires'
        $thrown | Should -Match 'Server Authentication'
        $thrown | Should -Match 'SAN missing wsus01.contoso.local'
        $thrown | Should -Not -Match 'SAN missing wsus.contoso.local'
    }
}
