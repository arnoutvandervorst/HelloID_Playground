
#Initialize default properties
$c = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json;
$m = $manager | ConvertFrom-Json;
$success = $False;

$account_guid = New-Guid

#Change mapping here
$account = [PSCustomObject]@{
    externalId = $account_guid;
}

if (-Not($dryRun -eq $True)) {
    #Write create logic here
}

#Get the SamAccountName from Person account data
$SamAccountName = $p.Accounts.MicrosoftActiveDirectory.SamAccountName;

#Construct the properties
$homeDirectory = "\\SERVER\Share\$SamAccountName"
$homeDrive = "H:"

#Get the user SID
$user = Get-ADUser -Identity $SamAccountName -Properties ObjectSID

if ($null -eq $user) {
    # Handle failure, exit script
}

#Create the home directory, suppress output
try {
    New-Item -Path $homeDirectory -ItemType Directory | Out-Null
}
catch {
    # Handle failure as exception
}

# Set NTFS rights
try {
    $acl = Get-ACL -Path $homeDirectory
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($user.ObjectSID, "Modify", "ContainerInherit, ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($rule) | Out-Null
    Set-Acl -Path $homeDirectory -AclObject $acl | Out-Null

    # Update AD user properties
    Set-ADUser -identity $SamAccountName -HomeDirectory $homeDirectory -HomeDrive $homeDrive | Out-Null

    $auditMessage = "Homedirectory created for: " + $p.DisplayName;

    $success = $True;
}
catch {
    # Handle failure as exception
}

#build up result
$result = [PSCustomObject]@{
    Success          = $success;
    AccountReference = $account_guid;
    AuditDetails     = $auditMessage;
    Account          = $account;
};

#send result back
Write-Output $result | ConvertTo-Json -Depth 10