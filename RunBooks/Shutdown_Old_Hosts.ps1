# Source Contol for this object is located in
<#[array]$RequiredModules = @(
	'Az.Accounts'
	'Az.Compute'
	'Az.Resources'
	'Az.Automation'
	'Az.DesktopVirtualization'
)
#>
########################################################################
#Set HostPool Variables for Script
$ResourceGroupName = ""
$HostPoolName = ""
$SubscriptionId = ""
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

# Get all Resource Manager resources from all resource groups
$ResourceGroups = Get-AzResourceGroup


foreach ($ResourceGroup in $ResourceGroups)
{    
   # Write-Output ("Showing resources in resource group " + $ResourceGroup.ResourceGroupName)
    $Resources = Get-AzResource -ResourceGroupName $ResourceGroup.ResourceGroupName
    foreach ($Resource in $Resources)
    {
#        Write-Output ($Resource.Name + " of type " +  $Resource.ResourceType)
    }#    Write-Output ("")
}



#Starting Script
Write-Output 'Starting the $HostPoolName Host Pool auto shutdown script. It will shutdown old versions of the hosts in the pool'

<#
# Write-Output 'Checking if required modules are installed in the Automation Account'
# Checking if required modules are present 
foreach ($ModuleName in $RequiredModules) {
    if (Get-Module -ListAvailable -Name $ModuleName) {
#        Write-Output "$($ModuleName) is present"
    } 
    else {
        Write-Output "$($ModuleName) is not present. Make sure to import the required modules in the Automation Account. Check the desription"
        #throw
    }
}
#>

$Hostpool = Get-AzWvdHostPool -SubscriptionId $SubscriptionId -Name $HostPoolName -ResourceGroupName $ResourceGroupName

# Getting Session hosts information
$SessionHosts = @(Get-AzWvdSessionHost -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName  -HostPoolName $HostPoolName)
if (!$SessionHosts) {
    Write-Output "There are no session hosts in the Hostpool $($HostPool.Name). Ensure that hostpool has session hosts"
    Write-Output 'End'
    return
}

#Evaluate eacht session hosts
foreach ($SessionHost in $Sessionhosts) 
{
    $Domain,$SessionHostName = $SessionHost.Name.Split("/")
    $VMinstance,$DomainName,$ToplevelDomain = $SessionHostName.Split(".")
    #Gathering information about the running state
    $VMStatus = (Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMinstance -Status).Statuses[1].Code
    #Gathering information about tags
    $VMSkip = (Get-AzVm -ResourceGroupName $ResourceGroupName -Name $VMinstance).Tags.Keys

    # If VM is Deallocated we can skip    
    if($VMStatus -eq 'PowerState/deallocated'){
        Write-Output "$SessionHostName already off ...... moving on"
        continue
    }

	if($VMStatus -eq 'PowerState/stopped'){
		Write-Output "$SessionHostName is in a stopped state, trying to deallocate"
		$StopVM = Stop-AzVM -Name $VMinstance -ResourceGroupName $ResourceGroupName -Force -AsJob
            
	}
	
    # If VM has skiptag we can skip
    if ($VMSkip -contains "SkipAutoShutdown") 
	{
        Write-Output "The VM '$SessionHostName' contains the SkipAutoShutdown tag so that means it's a new host and I can't do anything to it"
        continue
    }


    #for running vms
   if($VMStatus -eq 'PowerState/running'){
    Write-Output "$SessionHostName is powered on, checking for active sessions"
    #vm is running and has an active session, no action required
    if ($Sessionhost.Session -eq '1'  -and $Sessionhost.Status -eq 'Available'){
        Write-Output "$SessionHostName is running and has people logged in. Moving to the next host."
    }
    #VM is running but has no active session, time to deallocate VM
    if ($Sessionhost.Session -eq '0'  -and $Sessionhost.Status -eq 'Available'){
        Write-Output "$SessionHostName is running, but has no active sessions."
        Write-Output "Trying to deallocate $SessionHostName."
        $StopVM = Stop-AzVM -Name $VMinstance -ResourceGroupName $ResourceGroupName -Force -AsJob
    }   
}
  
}
Write-Output 'All VMs were shutdown that had no active connections'
Write-Output 'Disconnecting AZ Session'
# Disconnect
$DisconnectInfo = Disconnect-AzAccount

Write-Output 'End of Job'
