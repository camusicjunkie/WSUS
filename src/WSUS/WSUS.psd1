@{
    RootModule            = 'WSUS.psm1'
    ModuleVersion         = '0.1.0'
    GUID                  = 'eebe41de-1325-4a9f-b899-914cde34c8cc'
    Author                = 'John Steele'
    CompanyName           = 'Unknown'
    Copyright             = '(c) John Steele. All rights reserved.'
    Description           = 'Build, configure and maintain a two-node (upstream and replica) WSUS setup.'
    PowerShellVersion     = '5.1'
    CompatiblePSEditions  = @('Desktop')

    # Hand-listed: must match the files in Public/ (checked by tests/Module.Tests.ps1).
    FunctionsToExport     = @(
        'ConvertTo-WsusUpstream'
        'Get-WsusNodeStatus'
        'Set-WsusReplicaConfig'
    )
    CmdletsToExport       = @()
    VariablesToExport     = @()
    AliasesToExport       = @()

    PrivateData           = @{
        PSData = @{
            Tags         = @('WSUS', 'WindowsUpdate', 'UpdateServices')
            ProjectUri   = 'https://github.com/camusicjunkie/WSUS'
            LicenseUri   = 'https://github.com/camusicjunkie/WSUS/blob/main/LICENSE'
            ReleaseNotes = 'See CHANGELOG.md in the project repository.'
        }
    }
}
