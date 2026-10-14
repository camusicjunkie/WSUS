BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\helpers\TestSetup.ps1')
}

AfterAll {
    Remove-WsusTestEnvironment
}

Describe 'Assert-WsusAllUsersInstall' {
    It 'accepts a module under Program Files' {
        InModuleScope WSUS {
            { Assert-WsusAllUsersInstall -ModuleBase (Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules\WSUS\1.0.0') } |
                Should -Not -Throw
        }
    }

    It 'accepts a module under the system module path' {
        InModuleScope WSUS {
            { Assert-WsusAllUsersInstall -ModuleBase (Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\Modules\WSUS') } |
                Should -Not -Throw
        }
    }

    It 'rejects a per-user install' {
        InModuleScope WSUS {
            { Assert-WsusAllUsersInstall -ModuleBase 'C:\Users\jsmith\Documents\WindowsPowerShell\Modules\WSUS\1.0.0' } |
                Should -Throw '*all users*Install-Module*AllUsers*'
        }
    }

    It 'rejects a module imported from an arbitrary path' {
        InModuleScope WSUS {
            { Assert-WsusAllUsersInstall -ModuleBase 'C:\Scripts\WSUS' } | Should -Throw '*C:\Scripts\WSUS*'
        }
    }
}
