@{
    # Default rules plus 5.1 compatibility. CI fails on Error and Warning (build.ps1 -Task Analyze).
    # No blanket exclusions: suppress with an inline SuppressMessageAttribute and a justification.
    IncludeDefaultRules = $true
    Severity            = @('Error', 'Warning')

    Rules               = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1')
        }
        PSUseCompatibleCmdlets = @{
            compatibility = @('desktop-5.1.14393.206-windows')
        }
    }
}
