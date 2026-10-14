# Stub of the UpdateServices module (WSUS admin cmdlets) for tests. Parameter lists follow the
# Microsoft Learn cmdlet pages. Every body throws so an unmocked call fails loudly.
# Deny-WsusUpdate exists in the real module too; it is deliberately left out here because the
# WSUS module defines its own public Deny-WsusUpdate.

function Get-WsusServer {
    [CmdletBinding()]
    param ([string] $Name, [int] $PortNumber, [switch] $UseSsl)
    throw 'Stub Get-WsusServer called: mock it.'
}
function Invoke-WsusServerCleanup {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)] $UpdateServer,
        [switch] $CleanupObsoleteComputers, [switch] $CleanupObsoleteUpdates,
        [switch] $CleanupUnneededContentFiles, [switch] $CompressUpdates,
        [switch] $DeclineExpiredUpdates, [switch] $DeclineSupersededUpdates
    )
    throw 'Stub Invoke-WsusServerCleanup called: mock it.'
}
function Get-WsusProduct {
    [CmdletBinding()]
    param ([Parameter(ValueFromPipeline)] $UpdateServer, [string] $TitleIncludes)
    throw 'Stub Get-WsusProduct called: mock it.'
}
function Set-WsusProduct {
    [CmdletBinding()]
    param ([Parameter(ValueFromPipeline)] $InputObject, [switch] $Disable)
    throw 'Stub Set-WsusProduct called: mock it.'
}
function Get-WsusClassification {
    [CmdletBinding()]
    param ([Parameter(ValueFromPipeline)] $UpdateServer)
    throw 'Stub Get-WsusClassification called: mock it.'
}
function Set-WsusClassification {
    [CmdletBinding()]
    param ([Parameter(ValueFromPipeline)] $InputObject, [switch] $Disable)
    throw 'Stub Set-WsusClassification called: mock it.'
}
function Get-WsusComputer {
    [CmdletBinding()]
    param ([Parameter(ValueFromPipeline)] $UpdateServer, [string] $NameIncludes)
    throw 'Stub Get-WsusComputer called: mock it.'
}
function Get-WsusUpdate {
    [CmdletBinding()]
    param ([Parameter(ValueFromPipeline)] $UpdateServer, $Approval, $Classification, $Status, [string] $UpdateId)
    throw 'Stub Get-WsusUpdate called: mock it.'
}
function Approve-WsusUpdate {
    [CmdletBinding()]
    param ([Parameter(ValueFromPipeline)] $Update, $Action, $Group, [datetime] $Deadline)
    throw 'Stub Approve-WsusUpdate called: mock it.'
}

# Stub of the Microsoft.UpdateServices.Administration enums.
# WARNING: names and values were guessed (research, issue #8). Verify once against a real node
# before any test compares values.
if (-not ('Microsoft.UpdateServices.Administration.SynchronizationResult' -as [type])) {
    Add-Type -TypeDefinition @'
namespace Microsoft.UpdateServices.Administration {
    public enum SynchronizationResult { Succeeded = 0, Failed = 1, Canceled = 2, NeverRun = 3 }
    public enum SynchronizationStatus { NotProcessing = 0, Running = 1 }
    public enum UpdateApprovalAction { Install = 0, All = 1, NotApproved = 2, Uninstall = 3 }
}
'@
}

# Stub of the Administration collection types used when assigning categories, classifications and groups.
if (-not ('Microsoft.UpdateServices.Administration.UpdateCategoryCollection' -as [type])) {
    Add-Type -TypeDefinition @'
namespace Microsoft.UpdateServices.Administration {
    public class UpdateCategoryCollection : System.Collections.ArrayList { }
    public class UpdateClassificationCollection : System.Collections.ArrayList { }
    public class ComputerTargetGroupCollection : System.Collections.ArrayList { }
}
'@
}

Export-ModuleMember -Function *
