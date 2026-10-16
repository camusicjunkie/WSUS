BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Enable-WsusApprovalRule' {
    BeforeEach {
        $script:fake = New-FakeWsusServer -Rules @(
            @{ Name = 'Critical and Security - Packer'; Enabled = $false },
            @{ Name = 'Default Automatic Approval Rule'; Enabled = $false }
        )
        Mock -ModuleName WSUS Get-WsusLocalFqdn { 'wsus01.contoso.local' }
        Mock -ModuleName WSUS Get-WsusServer { $script:fake }
    }

    It 'requires -Name so the stock Default rule is never turned on by accident' {
        (Get-Command Enable-WsusApprovalRule).Parameters['Name'].Attributes.Mandatory | Should -BeTrue
    }

    It 'turns only the named rules on and reports them as changed' {
        $result = Enable-WsusApprovalRule -Name 'Critical*'

        @($result).Count | Should -Be 1
        $result.PSObject.TypeNames | Should -Contain 'WSUS.ApprovalRule'
        $result.Enabled | Should -BeTrue
        $result.Changed | Should -BeTrue
        ($script:fake.Rules | Where-Object Name -like 'Default*').Enabled | Should -BeFalse
        $script:fake.Calls | Should -Contain 'Rule.Save:Critical and Security - Packer'
    }

    It 'changes nothing under -WhatIf' {
        $result = Enable-WsusApprovalRule -Name '*' -WhatIf

        @($result).Count | Should -Be 2
        $script:fake.Rules.Enabled | Should -Not -Contain $true
        $script:fake.Calls | Should -Not -Contain 'Rule.Save:Packer'
    }

    It 'throws on a replica, naming the node' {
        $script:fake = New-FakeWsusServer -IsReplica $true -Name 'wsus02.contoso.local'

        { Enable-WsusApprovalRule -Name '*' -WsusServer 'wsus02.contoso.local' } | Should -Throw "*'wsus02.contoso.local' is a Replica*"
    }

    It 'takes rule names from the pipeline' {
        $result = 'Critical and Security - Packer' | Enable-WsusApprovalRule

        $result.Name | Should -Be 'Critical and Security - Packer'
        $result.Enabled | Should -BeTrue
    }
}
