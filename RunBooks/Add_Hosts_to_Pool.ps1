# Source Contol for this object is located in X
Param(
    [Parameter(Mandatory=$false)]
    [ValidateRange(1, 65)]
    [string]$Number_of_Hosts = '2'
)
#65 due to need to update replica count in image gallery - 2 for every 20, but have seen max is 49

#Required Modules to be imported to Automation Account (Pay attention to the powershell version)
#   'Az.Accounts'
#   'Az.Compute'
#   'Az.Resources'
#   'Az.Automation'
#   'Az.DesktopVirtualization'
########################################################################
#Set HostPool Variables for Script
$resourceGroupName = ""
$Hostpool = ""
$SubsciptionID = ""
#Set Azure Compute Gallery Variables for Script
$GalleryName = "Azure_Virtual_Desktop_Image_Gallery"
$GalleryRG = "rg-image-gallery-001"
$ImageName = ""
#Naming for new VMs ("$VMNameRegion-$latestVersion")
$VMNameRegion = ""
#Template Spec ID
$id = ""
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

# Generate Registration Token
$GetToken = New-AzWvdRegistrationInfo -SubscriptionId $SubsciptionID -ResourceGroupName $resourceGroupName -HostPoolName $Hostpool -ExpirationTime (Get-Date).AddDays(14) -ErrorAction SilentlyContinue
Write-Output "A new token was generated. It is valid for 14 days.... unlesss there was already a token. In that case I did nothing.... You're welcome"
$token = (Get-AzWvdHostPoolRegistrationToken -ResourceGroupName $resourceGroupName -HostPoolName $Hostpool)

# Get the latest image version number
Write-Output "Determining latest image version to use from $GalleryName - $ImageName then using last 2 digits for VM name"
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
Write-Output "The latest image version number is $latestVersion"

# Set naming convention to include Image version
$vmNamePrefix = "$VMNameRegion-$latestVersion"

Write-Output "Getting the highest numbered host from $resourceGroupName and from $Hostpool"
# Get the list of session hosts in the host pool
$sessionHosts = Get-AzWvdSessionHost -ResourceGroupName $resourceGroupName -HostPoolName $Hostpool

# Extract the numbers from the session host names that match the specified prefix
$regex = "\d+"
$matchingNumbers = $sessionHosts.Name | ForEach-Object {
    $number = [regex]::Match($_, "$VMNameRegion-$latestVersion-(\d+)").Groups[1].Value
    if ($number -ne '') {
        [int]$number
    }
}

# If there are matching numbers, find the first gap in the sequence
if ($matchingNumbers) {
    $availableNumbers = 1..($matchingNumbers | Measure-Object -Maximum).Maximum | Where-Object {$_ -notin $matchingNumbers}
    $highestNumber = $availableNumbers[0]
} else {
    $highestNumber = 1
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
    } while ($existingVms.Name -contains "$vmNamePrefix-$highestNumber")
}

# Construct the name of the next host
$nextHostName = "$vmNamePrefix-$highestNumber"

# Output the name of the next host
Write-Output "The next session host is number that is free is $highestNumber - making the first VM's name $nextHostName"

Write-Output "Attempting to deploy new host to pool."
Write-Output "You can check the statuson the "$Hostpool" activity log, or look at deployments on the left pane in the RG "$resourceGroupName""
Write-Output "It will take at least 90 seconds to show"
Write-Output "When this deployment is done I will tag the new VMs with 'SkipAutoShutdown' = 'true' - Ensure this is complete"
New-AzResourceGroupDeployment -TemplateSpecID $id -ResourceGroupName $resourceGroupName -hostpoolToken $token.token -vmInitialNumber $highestNumber -vmNumberOfInstances $Number_of_Hosts -vmNamePrefix $vmNamePrefix

# Tagging VMs meeting naming convention with "SkipAutoShutdown" to true so that other automation does not run against"
$existingVMs = Get-AzVM -ResourceGroupName $resourceGroupName

foreach ($vm in $existingVMs) {
    if ($vm.Name -like "$vmNamePrefix*") {
        $tags = $vm.Tags
        $tags['SkipAutoShutdown'] = 'true'
        Set-AzResource -ResourceId $vm.Id -Tag $tags -Force
     }
}
Write-Output 'Disconnecting AZ Session'
#disconnect
$DisconnectInfo = Disconnect-AzAccount
Write-Output 'End of Job'
