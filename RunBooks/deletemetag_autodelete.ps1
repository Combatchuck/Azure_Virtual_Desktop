<#$RequiredModules 
	'Az.Accounts'
	'Az.Compute'
	'Az.Resources'
	'Az.Automation'
	'Az.DesktopVirtualization'
#>
<#
deleteme added as a tag to a vm will 
1 - place in drain mode
2 - Power off with no connections
3 - Delete when powered off
I recomend giving each task time to complete with the schedule
each time the automation runs, it only completes one part of the task to reduce impact
#>
########################################################################
# Set Variables for Script
$ResourceGroupName = ""
$HostPoolName = ""
$SubscriptionId = ""
########################################################################

# Authenticating

Write-Output "Logging in as automation's account system assigned Managed Identity"

try {
    "Connecting in to Azure..."
    Connect-AzAccount -Identity
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}

# Get all Resource Manager resources from the specified resource group
$Resources = Get-AzResource -ResourceGroupName $ResourceGroupName

# Starting Script
Write-Output "Starting the $HostPoolName Host Pool cleanup script."

$Hostpool = Get-AzWvdHostPool -SubscriptionId $SubscriptionId -Name $HostPoolName -ResourceGroupName $ResourceGroupName

# Getting Session hosts information
$SessionHosts = @(Get-AzWvdSessionHost -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -HostPoolName $HostPoolName)
if (!$SessionHosts) {
    Write-Output "There are no session hosts in the Hostpool $($HostPool.Name). Ensure that hostpool has session hosts"
    Write-Output "End"
    return
}

# Evaluate each session host
foreach ($SessionHost in $SessionHosts) {
    $Domain, $SessionHostName = $SessionHost.Name.Split("/")
    $VMInstance, $DomainName, $ToplevelDomain = $SessionHostName.Split(".")

    # Gathering information about the running state
    $VMStatus = (Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMInstance -Status).Statuses[1].Code

    # Gathering information about tags
    $VMTags = (Get-AzVm -ResourceGroupName $ResourceGroupName -Name $VMInstance).Tags

    # Check if the VM has the "deleteme" tag
    if ($VMTags.ContainsKey("deleteme")) {
        Write-Output "$SessionHostName has the 'deleteme' tag. Placing it in drain mode."

        # Place the VM in drain mode to prevent new sessions
        Update-AzWvdSessionHost -ResourceGroupName $ResourceGroupName -HostPoolName $HostPoolName -Name $SessionHostName -AllowNewSession:$False

        # Check if the VM is running and has no active connections
        if ($VMStatus -eq 'PowerState/running') {
            Write-Output "$SessionHostName is powered on, checking for active sessions."
            
            if ($SessionHost.Session -eq '0' -and $SessionHost.Status -eq 'Available') {
                Write-Output "$SessionHostName is running but has no active sessions. Shutting down the VM."

                # Shut down the VM
                Stop-AzVM -Name $VMInstance -ResourceGroupName $ResourceGroupName -Force -AsJob
            } else {
                Write-Output "$SessionHostName has active sessions, skipping shutdown for now."
                continue
            }
        }

        # If VM is stopped or deallocated, remove from the host pool and delete the VM
        if ($VMStatus -eq 'PowerState/deallocated' -or $VMStatus -eq 'PowerState/stopped') {
            Write-Output "$SessionHostName is in a stopped or deallocated state. Removing from host pool and deleting the VM."

            # Remove from the host pool
            Remove-AzWvdSessionHost -ResourceGroupName $ResourceGroupName -HostPoolName $HostPoolName -Name $SessionHostName

            # Delete the VM
            Remove-AzResource -ResourceGroupName $ResourceGroupName -ResourceName $VMInstance -ResourceType "Microsoft.Compute/virtualMachines" -Force
        }
    } else {
        Write-Output "$SessionHostName does not have the 'deleteme' tag. Skipping."
    }
}

Write-Output 'All VMs were processed.'
Write-Output 'Disconnecting AZ Session'

# Disconnect
$DisconnectInfo = Disconnect-AzAccount

Write-Output 'End of Job'
