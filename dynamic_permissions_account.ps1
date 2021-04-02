$p = $person | ConvertFrom-Json;
$m = $manager | ConvertFrom-Json;
$aRef = $accountReference | ConvertFrom-Json;
$mRef = $managerAccountReference | ConvertFrom-Json;
$pRef = $permissionReference | ConvertFrom-json;
$c = $configuration | ConvertFrom-Json;
$notFoundTag = "no_ad_group_for";

# Operation is a script parameter which contains the action HelloID wants to perform for this permission
# It has one of the following values: "grant", "revoke", "update"
$o = $operation | ConvertFrom-Json;

if ($dryRun -eq $True) {
    # Operation is empty for preview (dry run) mode, that's why we set it here.
    $o = "grant";
}

Write-Verbose -Verbose "DryRun: $dryRun"

$success = $True;
$auditLogs = New-Object Collections.Generic.List[PSCustomObject];
$dynamicPermissions = New-Object Collections.Generic.List[PSCustomObject];

$SamAccountName = $p.Accounts.MicrosoftActiveDirectory.SamAccountName
if ([String]::IsNullOrEmpty($SamAccountName)) {
    # Exit when empty!
    $result = [PSCustomObject]@{
        Success            = $False;
        DynamicPermissions = $dynamicPermissions;
        AuditLogs          = $auditLogs;
    };
    Write-Output $result | ConvertTo-Json -Depth 10;
    exit
}

Write-Verbose -Verbose $SamAccountName
Write-Verbose -Verbose "Operation: $o"

$currentPermissions = @{};
foreach ($permission in $pRef.CurrentPermissions) {
    $currentPermissions[$permission.Reference.Id] = $permission.DisplayName;
}

if ($currentPermissions.Count -eq 0) {
    Write-Verbose -Verbose "Current permissions are empty..."
}

$desiredPermissions = @{};
foreach ($contract in $p.Contracts) {
    if ($contract.Context.InConditions -or $dryRun -eq $false) {
        try {
            $properties = @("objectGUID", "name")
            $filter = "*$($contract.CostCenter.Code)_Algemeen"

            Write-Verbose -Verbose $filter

            $adGroup = Get-ADGroup -Filter { name -like $filter } -Properties $properties | Select-Object -First 1

            if ($null -ne $adGroup) {
                Write-Verbose -Verbose "Group found: $($adGroup.name)"
                $desiredPermissions[[string]$adGroup.objectGUID] = $adGroup.name;
            }
            else {
                Write-Verbose -Verbose "Group not found..."
                $desiredPermissions[$notFoundTag + ":" + $filter] = $filter;
            }
        }
        catch {
            $errResponse = $_;
            Write-Error $errResponse
        }
    }
}

if ($desiredPermissions.Count -eq 0) {
    Write-Verbose -Verbose "Desired permissions are empty..."
}

# Compare desired with current permissions and grant permissions
foreach ($permission in $desiredPermissions.GetEnumerator()) {
    $dynamicPermissions.Add([PSCustomObject]@{
            DisplayName = $permission.Value;
            Reference   = [PSCustomObject]@{ Id = $permission.Name };
        });

    if ($permission.Name -match $notFoundTag) { continue; }

    if (-Not $currentPermissions.ContainsKey($permission.Name) -and $dryRun -eq $false) {
        try {
            $adGroupMembers = Get-ADGroupMember -Identity $permission.name | Select-Object -ExpandProperty SamAccountName

            if ($adGroupMembers -contains $SamAccountName) {
                Write-Verbose -Verbose "$SamAccountName is already member of $($permission.Value)";

                $auditLogs.Add([PSCustomObject]@{
                        Action  = "GrantDynamicPermission";
                        Message = "Permission is already granted for $($permission.Value)";
                        IsError = $False;
                    });
            }
            else {
                Write-Verbose -Verbose "Granting $($permission.value) to $SamAccountName"
                Add-ADGroupMember -Identity $permission.Name -Members @($SamAccountName)
                $auditLogs.Add([PSCustomObject]@{
                        Action  = "GrantDynamicPermission";
                        Message = "Granted access to $($permission.Value)";
                        IsError = $False;
                    });
            }
        }
        catch {
            $success = $False;
            $errResponse = $_;
            $auditLogs.Add([PSCustomObject]@{
                    Action  = "GrantDynamicPermission";
                    Message = "Error granting access to $($permission.Value)";
                    IsError = $True;
                });
            Write-Error $errResponse
        }
    }
}

# Compare current with desired permissions and revoke permissions
$newCurrentPermissions = @{};
foreach ($permission in $currentPermissions.GetEnumerator()) {
    if (-Not $desiredPermissions.ContainsKey($permission.Name) -and $dryRun -eq $False) {
        try {
            Write-Verbose -Verbose "Revoking $($permission.value) from $SamAccountName"

            if ($permission.Name -notmatch $notFoundTag) {
                Remove-ADGroupMember -Identity $permission.Name -Members $SamAccountName -Confirm:$false
            }

            $auditLogs.Add([PSCustomObject]@{
                    Action  = "RevokeDynamicPermission";
                    Message = "Revoked access to $($permission.Value)";
                    IsError = $False;
                });
        }
        catch {
            $success = $False;
            $errResponse = $_;
            $auditLogs.Add([PSCustomObject]@{
                    Action  = "RevokeDynamicPermission";
                    Message = "Failed to revoke access to $($permission.Value)";
                    IsError = $True;
                });
            Write-Error $errResponse
        }
    }
    else {
        $newCurrentPermissions[$permission.Name] = $permission.Value;
    }
}

# Update current permissions
if ($o -eq "update") {
    foreach ($permission in $newCurrentPermissions.GetEnumerator()) {
        $auditLogs.Add([PSCustomObject]@{
                Action  = "UpdateDynamicPermission";
                Message = "Updated access to $($permission.Value)";
                IsError = $False;
            });
    }
}

# Revoke permissions, make sure data is empty as the entire permission is revoked
if ($o -eq "revoke") {
    $dynamicPermissions = @();
    $auditLogs.Add([PSCustomObject]@{
            Action  = "RevokeDynamicPermission";
            Message = "Revoked the dynamic permission";
            IsError = $False;
        });
}

Write-Verbose -Verbose "About to send the results to HelloID"

Write-Verbose -Verbose "Current permissions"
foreach ($k in $currentPermissions.Keys) {
    Write-Verbose -Verbose "$k $($currentPermissions[$k])"
}

Write-Verbose -Verbose "Desired permissions"
foreach ($k in $desiredPermissions.Keys) {
    Write-Verbose -Verbose "$k $($desiredPermissions[$k])"
}

Write-Verbose -Verbose "Success: $success"

# Send results
$result = [PSCustomObject]@{
    Success            = $success;
    DynamicPermissions = $dynamicPermissions;
    AuditLogs          = $auditLogs;
};
Write-Output $result | ConvertTo-Json -Depth 10;
