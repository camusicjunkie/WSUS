function Invoke-WsusDatabaseQuery {
    <#
    .SYNOPSIS
        Runs a T-SQL batch against SUSDB in the Windows Internal Database (no timeout).
    .DESCRIPTION
        Coarse test-seam wrapper: one effect, no decisions. The SQL text lives in the caller.
    #>
    [CmdletBinding()]
    param (
        # WID named pipe to connect to.
        [Parameter(Mandatory)]
        [string] $Instance,

        # T-SQL batch to run against SUSDB.
        [Parameter(Mandatory)]
        [string] $Query
    )

    $connection = New-Object -TypeName System.Data.SqlClient.SqlConnection `
        -ArgumentList "Server=$Instance;Database=SUSDB;Integrated Security=SSPI;"
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        $command.CommandTimeout = 0
        $null = $command.ExecuteNonQuery()
    }
    finally {
        $connection.Dispose()
    }
}
