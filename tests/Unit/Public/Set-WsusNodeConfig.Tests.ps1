BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Set-WsusNodeConfig' {
    BeforeAll {
        $script:thumb = '0123456789ABCDEF0123456789ABCDEF01234567'
        $script:originalProgramFiles = $env:ProgramFiles
    }

    BeforeEach {
        # Point ProgramFiles at a temp tree holding a ClientWebService Web.config.
        $script:root = Join-Path ([IO.Path]::GetTempPath()) ('wsus-test-' + [guid]::NewGuid())
        $script:webConfig = Join-Path $script:root 'Update Services\WebServices\ClientWebService\Web.config'
        $null = New-Item -ItemType Directory -Path (Split-Path $script:webConfig) -Force
        Set-Content -LiteralPath $script:webConfig -Value @'
<configuration><system.web><httpRuntime executionTimeout="3600" maxRequestLength="4096" /></system.web></configuration>
'@
        $env:ProgramFiles = $script:root

        $script:fake = New-FakeWsusServer -Name 'wsus01.contoso.local'
        Mock -ModuleName WSUS Test-WsusElevated { $true }
        Mock -ModuleName WSUS Get-WsusLocalFqdn { 'wsus01.contoso.local' }
        Mock -ModuleName WSUS Test-WsusCertificate { }
        Mock -ModuleName WSUS Get-LocalGroupMember { }
        Mock -ModuleName WSUS Add-LocalGroupMember { }
        Mock -ModuleName WSUS Set-WsusAppPoolSetting { }
        Mock -ModuleName WSUS Grant-WsusFileAccess { }
        Mock -ModuleName WSUS Set-WsusSslBinding { }
        Mock -ModuleName WSUS Invoke-WsusUtil { }
        Mock -ModuleName WSUS Restart-WsusService { }
        Mock -ModuleName WSUS Get-WsusServer { $script:fake }
    }

    AfterEach {
        $env:ProgramFiles = $script:originalProgramFiles
        Remove-Item -LiteralPath $script:root -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'successful run' {
        It 'returns a WSUS.NodeConfig with a passed self-test and no role' {
            $result = Set-WsusNodeConfig -SslCertThumbprint $script:thumb -VipFqdn 'wsus.contoso.local' -Domain 'CONTOSO'

            $result.PSObject.TypeNames | Should -Contain 'WSUS.NodeConfig'
            $result.ComputerName | Should -Be $env:COMPUTERNAME
            $result.Certificate | Should -Be $script:thumb
            $result.SelfTest | Should -Be 'Passed'
            $result.NextStep | Should -Be 'Upstream node: Set-WsusUpstreamConfig. Replica node: Set-WsusReplicaConfig.'
            $result.PSObject.Properties.Name | Should -Not -Contain 'Role'
        }
    }

    Context 'certificate preflight' {
        It 'checks the certificate against the VIP and node FQDN' {
            $null = Set-WsusNodeConfig -SslCertThumbprint $script:thumb -VipFqdn 'wsus.contoso.local' -Domain 'CONTOSO'

            Should -Invoke -ModuleName WSUS Test-WsusCertificate -Times 1 -ParameterFilter {
                $Thumbprint -eq '0123456789ABCDEF0123456789ABCDEF01234567' -and
                $RequiredName -contains 'wsus.contoso.local' -and $RequiredName -contains 'wsus01.contoso.local'
            }
        }

        It 'changes nothing when the certificate is rejected' {
            Mock -ModuleName WSUS Test-WsusCertificate { throw 'Certificate rejected: no private key' }

            { Set-WsusNodeConfig -SslCertThumbprint $script:thumb -VipFqdn 'wsus.contoso.local' -Domain 'CONTOSO' } |
                Should -Throw '*rejected*'
            Should -Invoke -ModuleName WSUS Add-LocalGroupMember -Times 0
            Should -Invoke -ModuleName WSUS Set-WsusAppPoolSetting -Times 0
            Should -Invoke -ModuleName WSUS Set-WsusSslBinding -Times 0
            Should -Invoke -ModuleName WSUS Restart-WsusService -Times 0
        }
    }

    Context 'admin access' {
        It 'adds the admin resource group to WSUS Administrators when it is not a member' {
            $null = Set-WsusNodeConfig -SslCertThumbprint $script:thumb -VipFqdn 'wsus.contoso.local' -Domain 'CONTOSO'

            Should -Invoke -ModuleName WSUS Add-LocalGroupMember -Times 1 -ParameterFilter {
                "$Group" -eq 'WSUS Administrators' -and "$Member" -eq 'CONTOSO\res.srv.wsus.admin'
            }
        }

        It 'leaves membership alone when the group is already a member' {
            Mock -ModuleName WSUS Get-LocalGroupMember { [PSCustomObject] @{ Name = 'CONTOSO\res.srv.wsus.admin' } }

            $null = Set-WsusNodeConfig -SslCertThumbprint $script:thumb -VipFqdn 'wsus.contoso.local' -Domain 'CONTOSO'

            Should -Invoke -ModuleName WSUS Add-LocalGroupMember -Times 0
        }
    }

    Context 'tuning and SSL' {
        It 'applies the WsusPool tuning table' {
            $null = Set-WsusNodeConfig -SslCertThumbprint $script:thumb -VipFqdn 'wsus.contoso.local' -Domain 'CONTOSO'

            Should -Invoke -ModuleName WSUS Set-WsusAppPoolSetting -Times 1 -ParameterFilter {
                $Setting['queueLength'] -eq 2000 -and $Setting['failure.rapidFailProtection'] -eq $false -and
                $Setting['failure.loadBalancerCapabilities'] -eq 'TcpLevel'
            }
        }

        It 'raises the ClientWebService limits, backing up the original web.config once' {
            $null = Set-WsusNodeConfig -SslCertThumbprint $script:thumb -VipFqdn 'wsus.contoso.local' -Domain 'CONTOSO'

            [xml] $config = Get-Content -LiteralPath $script:webConfig -Raw
            $config.configuration.'system.web'.httpRuntime.executionTimeout | Should -Be '7200'
            $config.configuration.'system.web'.httpRuntime.maxRequestLength | Should -Be '204800'
            "$($script:webConfig).orig" | Should -Exist
            ([xml] (Get-Content -LiteralPath "$($script:webConfig).orig" -Raw)).configuration.'system.web'.httpRuntime.executionTimeout |
                Should -Be '3600'
            Should -Invoke -ModuleName WSUS Grant-WsusFileAccess -Times 1 -ParameterFilter { $Path -eq $script:webConfig }

            $null = Set-WsusNodeConfig -SslCertThumbprint $script:thumb -VipFqdn 'wsus.contoso.local' -Domain 'CONTOSO'
            ([xml] (Get-Content -LiteralPath "$($script:webConfig).orig" -Raw)).configuration.'system.web'.httpRuntime.executionTimeout |
                Should -Be '3600'
        }

        It 'binds the certificate and configures SSL for the VIP' {
            $null = Set-WsusNodeConfig -SslCertThumbprint $script:thumb -VipFqdn 'wsus.contoso.local' -Domain 'CONTOSO'

            Should -Invoke -ModuleName WSUS Set-WsusSslBinding -Times 1 -ParameterFilter { $Thumbprint -eq '0123456789ABCDEF0123456789ABCDEF01234567' }
            Should -Invoke -ModuleName WSUS Invoke-WsusUtil -Times 1 -ParameterFilter {
                $ArgumentList -contains 'configuressl' -and $ArgumentList -contains 'wsus.contoso.local'
            }
        }
    }

    Context 'restart and self-test' {
        It 'always restarts IIS and the WSUS service and waits 20 seconds' {
            $null = Set-WsusNodeConfig -SslCertThumbprint $script:thumb -VipFqdn 'wsus.contoso.local' -Domain 'CONTOSO'

            Should -Invoke -ModuleName WSUS Restart-WsusService -Times 1 -ParameterFilter { $Sleep -eq 20 }
        }

        It 'self-tests the local node over SSL on 8531' {
            $null = Set-WsusNodeConfig -SslCertThumbprint $script:thumb -VipFqdn 'wsus.contoso.local' -Domain 'CONTOSO'

            Should -Invoke -ModuleName WSUS Get-WsusServer -Times 1 -ParameterFilter {
                $Name -eq 'wsus01.contoso.local' -and $PortNumber -eq 8531 -and $UseSsl
            }
        }

        It 'writes a non-terminating error and still returns the result when the self-test fails' {
            Mock -ModuleName WSUS Get-WsusServer { throw 'connection refused' }

            $result = Set-WsusNodeConfig -SslCertThumbprint $script:thumb -VipFqdn 'wsus.contoso.local' -Domain 'CONTOSO' -ErrorVariable err -ErrorAction SilentlyContinue

            $result.SelfTest | Should -Match '^Failed: .*wsus01\.contoso\.local.*8531'
            $err | Should -Not -BeNullOrEmpty
        }
    }

    Context 'guards and -WhatIf' {
        It 'throws when not elevated, before changing anything' {
            Mock -ModuleName WSUS Test-WsusElevated { $false }

            { Set-WsusNodeConfig -SslCertThumbprint $script:thumb -VipFqdn 'wsus.contoso.local' -Domain 'CONTOSO' } |
                Should -Throw '*elevated*'
            Should -Invoke -ModuleName WSUS Restart-WsusService -Times 0
        }

        It 'returns nothing and changes nothing under -WhatIf' {
            $result = Set-WsusNodeConfig -SslCertThumbprint $script:thumb -VipFqdn 'wsus.contoso.local' -Domain 'CONTOSO' -WhatIf

            $result | Should -BeNullOrEmpty
            Should -Invoke -ModuleName WSUS Add-LocalGroupMember -Times 0
            Should -Invoke -ModuleName WSUS Set-WsusAppPoolSetting -Times 0
            Should -Invoke -ModuleName WSUS Grant-WsusFileAccess -Times 0
            Should -Invoke -ModuleName WSUS Set-WsusSslBinding -Times 0
            Should -Invoke -ModuleName WSUS Invoke-WsusUtil -Times 0
            Should -Invoke -ModuleName WSUS Restart-WsusService -Times 0
            ([xml] (Get-Content -LiteralPath $script:webConfig -Raw)).configuration.'system.web'.httpRuntime.executionTimeout |
                Should -Be '3600'
        }
    }
}
