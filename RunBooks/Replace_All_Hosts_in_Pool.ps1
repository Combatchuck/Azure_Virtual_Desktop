# Required Modules to be imported to Automation Account (Pay attention to the powershell version)
#   'Az.Accounts'
#   'Az.Compute'
#   'Az.Resources'
#   'Az.Automation'
#   'Az.DesktopVirtualization'
########################################################################
# Set HostPool Variables for Script
$resourceGroupName = "<>"
$Hostpool = "<>"
$SubsciptionID = "<>"
# Set Azure Compute Gallery Variables for Script
$GalleryName = "<>"
$GalleryRG = "<>"
$ImageName = "<>"
# Naming for new VMs ("$VMNameRegion-$latestVersion")
$VMNameRegion = "AVD-<TWO_LETTER_REGION>"
# Template Spec ID
$id = "<ID of TEMPLATE SPEC)>"
########################################################################

# Authenticating
Write-Output "Logging in as automation's account system assigned Managed Identy"

try

{
    "Connecting in to Azure..."
    Connect-AzAccount -Identity
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}

# Remove all the Old VMs from the pool based off not being the most current name in the pool, and not based off the new image. Requires delete tag to be present
Write-Output "Removing all the VMs that have been already tagged and no longer have a place in the pool"
$existingVMs = Get-AzVM -ResourceGroupName $resourceGroupName
foreach ($vm in $existingVMs) {
    $tags = $vm.Tags
    if ($tags -and $tags.ContainsKey('delete-when-unused') -and $tags['delete-when-unused'] -eq 'true') {
        $vmName = $vm.Name
        Remove-AzResource -ResourceId $vm.Id -Force
        $nic = Get-AzNetworkInterface -ResourceGroupName $resourceGroupName | Where-Object { $_.Name -like "$vmName*" }
        if ($nic) {
            Remove-AzNetworkInterface -ResourceGroupName $resourceGroupName -Name $nic.Name -Force
        }
        $disk = Get-AzDisk -ResourceGroupName $resourceGroupName | Where-Object { $_.Name -like "$vmName*" }
        if ($disk) {
            Remove-AzDisk -ResourceGroupName $resourceGroupName -DiskName $disk.Name -Force
        }
        $sessionHost = Get-AzWvdSessionHost -ResourceGroupName $resourceGroupName -HostPoolName $Hostpool | Where-Object { $_.Name -eq $vmName }
        if ($sessionHost) {
            Remove-AzWvdSessionHost -ResourceGroupName $resourceGroupName -HostPoolName $Hostpool -Name $vmName -Force
        }
    }
}



# Generate Registration Token
$GetToken = New-AzWvdRegistrationInfo -SubscriptionId $SubsciptionID -ResourceGroupName $resourceGroupName -HostPoolName $Hostpool -ExpirationTime (Get-Date).AddDays(14) -ErrorAction SilentlyContinue
Write-Host "A new token was generated. It is valid for 14 days.... unlesss there was already a token. In that case I did nothing.... You're welcome"
$token = (Get-AzWvdHostPoolRegistrationToken -ResourceGroupName $resourceGroupName -HostPoolName $Hostpool)

# Get the latest image version number
Write-Host "Determining latest image version to use from $GalleryName - $ImageName then using last 2 digits for VM name"
$imageVersions = Get-AzGalleryImageVersion -GalleryName $GalleryName -ResourceGroupName $GalleryRG -GalleryImageDefinitionName $ImageName
$HighestNumber = $imageVersions.Name | ForEach-Object {
    $versionComponents = $_ -split '\.'
    [PSCustomObject]@{
        Name = $_
        Major = [int]$versionComponents[0]
        Minor = [int]$versionComponents[1]
        Patch = [int]$versionComponents[2]
    }
} | Sort-Object -Property Major, Minor, Patch -Descending | Select-Object -ExpandProperty Name
$latestVersion = ($highestNumber -replace '\.', '-') | Sort-Object -Property Name -Descending | Select-Object -First 1
$latestVersion = ($latestVersion -split '^[^-]*-')[-1]

# Display the value of $highestVersion
Write-Output "The highest image version number is $latestVersion"

# Set naming convention to include Image version
$vmNamePrefix = "$VMNameRegion-$latestVersion"

Write-Output "Getting the highest numbered host from $resourceGroupName and from $Hostpool"
# Get the list of session hosts in the host pool
$sessionHosts = Get-AzWvdSessionHost -ResourceGroupName $resourceGroupName -HostPoolName $Hostpool

# Extract the numbers from the session host names that match the specified prefix and find the highest number
$regex = "\d+"
$matchingSessionHosts = $sessionHosts.Name | Where-Object { $_ -like "$vmNamePrefix*" }
if ($matchingSessionHosts) {
    $matchingNumbers = $matchingSessionHosts | Select-String -Pattern $regex | ForEach-Object { $_.Matches.Value }
    $highestNumber = ($matchingNumbers | Measure-Object -Maximum).Maximum
} else {
    $highestNumber = -1
}

# Ensure the highest number is not -1
if ($highestNumber -eq -1) {
    $highestNumber = 0
}

# Check if any VMs with the same name exist in the resource group
$existingVms = Get-AzVM -ResourceGroupName $resourceGroupName | Where-Object { $_.Name -like "$vmNamePrefix*" }

if ($existingVms) {
    # If there are existing VMs with the same name, increment the highest number until no matching VMs are found
   do {
       $highestNumber++
        $existingVms = Get-AzVM -ResourceGroupName $resourceGroupName | Where-Object { $_.Name -like "$vmNamePrefix*$highestNumber" }
    } while ($existingVms)
}

# Construct the name of the next host
$nextHostName = "$vmNamePrefix-$($highestNumber)"

# Output the name of the next host
Write-Host "The next session host is number that is free is $highestNumber - making the first vms name $nextHostName"

Write-Host "Attempting to deploy new host to pool."
Write-Host "You can check the statuson the "$Hostpool" activity log, or look at deployments on the left pane in the RG $resourceGroupName"
Write-Host "It will take at least 90 seconds to show"

$Number_of_Hosts = $sessionHosts.Count
if ($Number_of_Hosts -eq 0) {Write-Host "There are no hosts in the pool and this isnt going to do anything. Use the $Hostpool specfic Automation Account and enter the number of hosts needed"}
New-AzResourceGroupDeployment -TemplateSpecID $id -ResourceGroupName $resourceGroupName -hostpoolToken $token.token -vmInitialNumber $highestNumber -vmNumberOfInstances $Number_of_Hosts -vmNamePrefix $vmNamePrefix

# Tagging VMs meeting naming convention with "SkipAutoShutdown" to true"
$existingVMs = Get-AzVM -ResourceGroupName $resourceGroupName

foreach ($vm in $existingVMs) {
    if ($vm.Name -like "$vmNamePrefix*") {
        $tags = $vm.Tags
        $tags['SkipAutoShutdown'] = 'true'
        Set-AzResource -ResourceId $vm.Id -Tag $tags -Force
     }
}

# Tagging VMs not meeting naming convention with "no-scaling"
$existingVMs = Get-AzVM -ResourceGroupName $resourceGroupName

foreach ($vm in $existingVMs) {
    if ($vm.Name -notlike "$vmNamePrefix*") {
        $tags = $vm.Tags
        $tags['no-scaling'] = 'true'
        $tags['delete-when-unused'] = 'true'
        $tags.Remove('SkipAutoShutdown')
        Set-AzResource -ResourceId $vm.Id -Tag $tags -Force
        Write-Host "The VM $($vm.Name) has been tagged with 'no-scaling' and 'delete-when-unused'."
    }
}

Write-Output 'Disconnecting AZ Session'
$DisconnectInfo = Disconnect-AzAccount
Write-Output 'End of Job'
