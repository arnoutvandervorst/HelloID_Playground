# Initialize default properties
$a = $account | ConvertFrom-Json;
$mail = $a.AdditionalFields.userPrincipalName
$connectionString = "Server=<SERVER>;Database=<DATABASE>;Integrated Security=True"
$sqlGet = "SELECT * from blackList where email = '$mail'"
$sqlInsert = "Insert into blackList (email) VALUES ('$mail')"

# Result when field is unique
$successResult = [PSCustomObject]@{
    Success         = $True;
    NonUniqueFields = @()
};

# Result when field is NOT unique
$nonUniqueResult = [PSCustomObject]@{
    Success         = $True;
    NonUniqueFields = @('AdditionalFields.userPrincipalName')
};

# Result when check failed
$failureResult = [PSCustomObject]@{
    Success         = $False;
    NonUniqueFields = @()
};

if ($dryRun -eq $True) {
    Write-Verbose -Verbose "Dry run for uniqueness check on external systems"
}

if ([String]::IsNullOrEmpty($mail)) {
    Write-Output $failureResult | ConvertTo-Json -Depth 2
    exit
}

Write-Verbose -Verbose $mail

try {
    Write-Verbose -Verbose "Opening connection..."
    $conn = New-Object System.Data.SqlClient.SqlConnection
    $conn.ConnectionString = $connectionString
    $conn.Open()
}
catch {
    Write-Verbose -Verbose $_

    Write-Output $failureResult | ConvertTo-Json -Depth 2
    exit
}

try {
    Write-Verbose -Verbose "Retrieving data..."
    $blackListTable = New-Object System.Data.DataTable
    $cmd = New-Object System.Data.SqlClient.SqlCommand($sqlGet, $conn)
    $cmd.CommandTimeout = 600
    $data = $cmd.ExecuteReader()
    [void]$blackListTable.Load($data)
}
catch {
    Write-Verbose -Verbose $_

    Write-Output $failureResult | ConvertTo-Json -Depth 2
    exit
}

if ($blackListTable.Rows.Count -eq 0) {
    if ($dryRun -ne $True) {
        try {
            $cmd = New-Object System.Data.SqlClient.SqlCommand($sqlInsert, $conn)
            [void]$cmd.ExecuteNonQuery()
        }
        catch {
            Write-Verbose -Verbose $_

            Write-Output $failureResult | ConvertTo-Json -Depth 2
            exit
        }
    }

    #The value is unique AND added to the blacklist
    Write-Verbose -Verbose "Email is unique"

    Write-Output $successResult | ConvertTo-Json -Depth 2
    exit
}
else {
    Write-Verbose -Verbose "Email is not unique"

    Write-Output $nonUniqueResult | ConvertTo-Json -Depth 2
    exit
}

$conn.Close()

Write-Output $failureResult | ConvertTo-Json -Depth 2