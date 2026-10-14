BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'New-WsusAdminGroup' {
    BeforeEach {
        # Identity group exists; the resource group does not; no members yet.
        Mock -ModuleName WSUS Get-ADGroup {
            if ($Filter -like "*id.sa.platforms*") { [PSCustomObject] @{ Name = 'id.sa.platforms' } }
        }
        Mock -ModuleName WSUS New-ADGroup { }
        Mock -ModuleName WSUS Get-ADGroupMember { }
        Mock -ModuleName WSUS Add-ADGroupMember { }
    }

    Context 'resource group does not exist' {
        It 'creates it, nests the identity group, and returns a WSUS.AdminGroup' {
            $result = New-WsusAdminGroup

            $result.PSObject.TypeNames | Should -Contain 'WSUS.AdminGroup'
            $result.ResourceGroup | Should -Be 'res.srv.wsus.admin'
            $result.Member | Should -Be 'id.sa.platforms'
            $result.Created | Should -BeTrue
            $result.NextStep | Should -Be 'Install-WsusNode, then Set-WsusNodeConfig, on both nodes'
            Should -Invoke -ModuleName WSUS New-ADGroup -ParameterFilter {
                $Name -eq 'res.srv.wsus.admin' -and $GroupScope -eq 'DomainLocal' -and $GroupCategory -eq 'Security'
            } -Times 1
            Should -Invoke -ModuleName WSUS Add-ADGroupMember -ParameterFilter {
                $Identity -eq 'res.srv.wsus.admin' -and $Members -eq 'id.sa.platforms'
            } -Times 1
        }
    }

    Context 'resource group already exists' {
        BeforeEach {
            Mock -ModuleName WSUS Get-ADGroup { [PSCustomObject] @{ Name = 'x' } }
        }

        It 'does not create it and reports Created as false' {
            $result = New-WsusAdminGroup

            $result.Created | Should -BeFalse
            Should -Invoke -ModuleName WSUS New-ADGroup -Times 0
            Should -Invoke -ModuleName WSUS Add-ADGroupMember -Times 1
        }

        It 'leaves an existing membership in place' {
            Mock -ModuleName WSUS Get-ADGroupMember { [PSCustomObject] @{ SamAccountName = 'id.sa.platforms' } }

            $result = New-WsusAdminGroup

            $result.Member | Should -Be 'id.sa.platforms'
            Should -Invoke -ModuleName WSUS Add-ADGroupMember -Times 0
        }
    }

    Context 'identity group is missing' {
        It 'throws naming the group and changes nothing' {
            Mock -ModuleName WSUS Get-ADGroup { }

            { New-WsusAdminGroup } | Should -Throw -ExpectedMessage "*'id.sa.platforms' not found*"
            Should -Invoke -ModuleName WSUS New-ADGroup -Times 0
            Should -Invoke -ModuleName WSUS Add-ADGroupMember -Times 0
        }
    }

    Context '-WhatIf on a missing resource group' {
        It 'changes nothing, skips the membership step and reports Created as false' {
            $result = New-WsusAdminGroup -WhatIf

            $result.Created | Should -BeFalse
            Should -Invoke -ModuleName WSUS New-ADGroup -Times 0
            Should -Invoke -ModuleName WSUS Get-ADGroupMember -Times 0
            Should -Invoke -ModuleName WSUS Add-ADGroupMember -Times 0
        }
    }

    Context '-GroupPath' {
        It 'creates the group in the given OU' {
            New-WsusAdminGroup -GroupPath 'OU=Groups,DC=corp,DC=local' | Out-Null

            Should -Invoke -ModuleName WSUS New-ADGroup -ParameterFilter { $Path -eq 'OU=Groups,DC=corp,DC=local' } -Times 1
        }
    }

    Context 'ActiveDirectory module unavailable' {
        It 'throws the prerequisite error before touching AD' {
            Mock -ModuleName WSUS Assert-WsusPrerequisite { throw 'Prerequisites not met: ActiveDirectory' }

            { New-WsusAdminGroup } | Should -Throw '*ActiveDirectory*'
            Should -Invoke -ModuleName WSUS Assert-WsusPrerequisite -ParameterFilter { $Module -contains 'ActiveDirectory' } -Times 1
            Should -Invoke -ModuleName WSUS Get-ADGroup -Times 0
        }
    }
}
