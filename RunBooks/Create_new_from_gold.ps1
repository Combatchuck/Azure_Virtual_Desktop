#####################################
#Template Spec ID
$id = "<Template Spec ID for creating from latest image in gallery - string that has info inscluding Sub, RG and version of spec. Can be found in proprties on spec - Example in Create new from gold Template spec>
# RG for where to put non-domain joined machine for making a new machine
$RG = <>
######################################

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

#Something to make each machine "special"
# Get the current time in local time zone
$dateofcreate = Get-Date -Format "MM-dd"

Write-Output "A new host will be created as $dateofcreate in the rg-avd-build-001 RG"
Write-Output "Nothing will be displayed here till it completes. Go look in the RG"

New-AzResourceGroupDeployment -TemplateSpecID $id -ResourceGroupName $RG -networkInterfaceName "$dateofcreate-patch" -virtualMachineName "$dateofcreate-patch" -virtualMachineComputerName "$dateofcreate-patch"

Write-Output 'Disconnecting AZ Session'
$DisconnectInfo = Disconnect-AzAccount
Write-Output 'End of Job'
