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
$ResourceGroupName = "<>"
$HostPoolName = "<>"
$SubscriptionId = "<>"
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

#Get all Resource Manager resources from all resource groups
$ResourceGroups = Get-AzResourceGroup

foreach ($ResourceGroup in $ResourceGroups)
{    
   #Write-Output ("Showing resources in resource group " + $ResourceGroup.ResourceGroupName)
    $Resources = Get-AzResource -ResourceGroupName $ResourceGroup.ResourceGroupName
    foreach ($Resource in $Resources)
    {
#        Write-Output ($Resource.Name + " of type " +  $Resource.ResourceType)
    }#    Write-Output ("")
}



#starting script
Write-Output 'Starting AVD $HostPoolName Power On script'

Write-Output 'Checking if required modules are installed in the Automation Account'
# Checking if required modules are present 
foreach ($ModuleName in $RequiredModules) {
    if (Get-Module -ListAvailable -Name $ModuleName) 
    {
        Write-Output "$($ModuleName) is present"
    } 
    else {
        Write-Output "$($ModuleName) is not present. Make sure to import the required modules in the Automation Account. Check the desription"
        #throw
    }
}

#Getting Session hosts information
$Hostpool = Get-AzWvdHostPool -SubscriptionId b$SubscriptionId -Name $HostPoolName -ResourceGroupName $ResourceGroupName
$SessionHosts = @(Get-AzWvdSessionHost -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName  -HostPoolName $HostPoolName)
if (!$SessionHosts) {
    Write-Output "There are no session hosts in the Hostpool $($HostPool.Name). Ensure that hostpool has session hosts"
    Write-Output 'End'
    return
}
#Evaluate each session hosts
foreach ($SessionHost in $Sessionhosts) 
{
    $Domain,$SessionHostName = $SessionHost.Name.Split("/")
    $VMinstance,$DomainName,$ToplevelDomain = $SessionHostName.Split(".")
    #Gathering information about the running state
    $VMStatus = (Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMinstance -Status).Statuses[1].Code
    #Gathering information about tags
    $VMSkip = (Get-AzVm -ResourceGroupName $ResourceGroupName -Name $VMinstance).Tags.Keys
    # If VM is Powered On we can skip    
    if($VMStatus -eq 'PowerState/running'){
        Write-Output "$SessionHostName is in a running state, processing next session hosts"
        continue
    }
    # If VM has skiptag we can skip
    if ($VMSkip -contains "SkipAutoStartup") 
    {
        Write-Output "VM '$SessionHostName' contains the skip tag and will be ignored"
        continue
    }

    #for deallocate vms
    if($VMStatus -eq 'PowerState/deallocated'){
        Write-Output "$SessionHostName is deallocated"
       #VM is deallocated, then we need to power on
        if ($Sessionhost.Status -eq 'Unavailable'){
            Write-Output "$SessionHostName is powered down."
            Write-Output "This will take around 90 seconds. Trying to power on $SessionHostName."
            $StartVM = Start-AzVM -Name $VMinstance -ResourceGroupName $ResourceGroupName
            Write-Output "Starting $SessionhostName ended with status: $($StartVM.Status)"
            #Create Extra check
        }   
    }  
}
Write-Output 'All VMs were started that were shutdown'
Write-Output 'Disconnecting AZ Session'
#disconnect
$DisconnectInfo = Disconnect-AzAccount
Write-Output 'End of Job'
