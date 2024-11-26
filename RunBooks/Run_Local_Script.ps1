
########################################################################
# Set Variables for Script
$rgname = "<resource group name>"
#Script should be on VM to prevent perm issues
$ScriptToRun = "C:\<path-to-script>.ps1"
$Subscription = "<ID of Sub>"
########################################################################
# Authenticate with Azure
Write-Host "Connecting as Identity of Automation Account"
Connect-AzAccount -Identity

# Set the current context to the subscription and resource group that contain the VMs
Set-AzContext -SubscriptionId $Subscription

$ScriptContent = @"
& '$ScriptToRun'
"@
Out-File -InputObject $ScriptContent -FilePath ScriptWrapper.ps1 

# Get all VMs in the resource group
$vms = Get-AzVM -ResourceGroupName $rgname

ForEach ($vm in $vms) {
    $vmname = $vm.Name
    Write-Host "Running script on VM: $vmname"
    Invoke-AzVMRunCommand -ResourceGroupName $rgname -Name $vmname -CommandId 'RunPowerShellScript' -ScriptPath ScriptWrapper.ps1
}

Remove-Item -Path ScriptWrapper.ps1

Write-Output 'Disconnecting AZ Session'
$DisconnectInfo = Disconnect-AzAccount
Write-Output 'End of Job'
