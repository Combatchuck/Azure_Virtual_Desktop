<#
RequiredModules 

	'Az.Accounts'
	'Az.Compute'
	'Az.Resources'
	'Az.Automation'
	'Az.DesktopVirtualization'
#>
<#
Check RGs for Nic and Disks not deleted when VMs were removed
#>
########################################################################
# Specify the resource groups to check
$ResourceGroupNames = @("rg1", "rg2", "rg3")
########################################################################

# Authenticating
Write-Output "Logging in as automation's account system assigned Managed Identity"

try {
    "Connecting to Azure..."
    Connect-AzAccount -Identity
} catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}

# Loop through each specified resource group
foreach ($ResourceGroupName in $ResourceGroupNames) {
    Write-Output "Checking resource group: $ResourceGroupName"

    # Get all unattached NICs and delete them
    $unattachedNICs = Get-AzNetworkInterface | Where-Object { $_.VirtualMachine -eq $null -and $_.ResourceGroupName -eq $ResourceGroupName }
    foreach ($nic in $unattachedNICs) {
        Remove-AzNetworkInterface -Name $nic.Name -ResourceGroupName $ResourceGroupName -Force
    }

    # Get all unattached disks and delete them
    $unattachedDisks = Get-AzDisk | Where-Object { $_.ManagedBy -eq $null -and $_.ResourceGroupName -eq $ResourceGroupName }
    foreach ($disk in $unattachedDisks) {
        Remove-AzDisk -ResourceGroupName $disk.ResourceGroupName -DiskName $disk.Name -Force
    }
}
