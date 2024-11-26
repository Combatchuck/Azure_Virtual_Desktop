###########################################################################
#SET INFO FOR SCRIPT
#Image Gallery Information
$GALLERYNAME = <>
#GALLERYRGNAME = <>
$GALLERYDEFF = <>
#####################################
#Template Spec Information
$id = "<CHANGE TO POINT AT TEMPLATE SPEC - Example in Capture host to gallery template spec>"
$TemplateSpecRG = <>
###########################################################################

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

# Get the latest image version number
Write-Host "Determining next host number available for use"
$imageVersions = Get-AzGalleryImageVersion -GalleryName "$GALLERYNAME" -ResourceGroupName "#GALLERYRGNAME" -GalleryImageDefinitionName "$GALLERYDEFF"

$HighestNumber = $imageVersions.Name | ForEach-Object {
    $versionComponents = $_ -split '\.'
    [PSCustomObject]@{
        Name = $_
        Major = [int]$versionComponents[0]
        Minor = if($versionComponents.Count -ge 2){ [int]$versionComponents[1] } else { 0 }
        Patch = if($versionComponents.Count -ge 3){ [int]$versionComponents[2] } else { 0 }
    }
} | Sort-Object -Property Major, Minor, Patch -Descending | Select-Object -ExpandProperty Name

$latestVersion = $highestNumber | Sort-Object -Property @{Expression={[version]($_)}} -Descending | Select-Object -First 1

$nextPatchVersion = '{0}.{1}.{2:00}' -f $latestVersion.Major, $latestVersion.Minor, (Get-Date).Month

# Get the current time in local time zone
$dateofcreate = Get-Date -Format "MM-dd"
$sourceVmId = "$dateofcreate-patch"

#VM for Capture
$sourceVmId = "$dateofcreate-patch"
Write-Host ""

#Getting EOL date
$format = "yyyy-MM-ddTHH:mm:ss.fffZ"
$date = Get-Date
$utcDate = Get-Date -Date $date.ToUniversalTime() -Format $format
$futureDate = $date.AddDays(40).ToUniversalTime().ToString($format)

Write-Host "$sourceVmId will be captured to $GALLERYNAME - $GALLERYDEFF as $nextPatchVersion. $futureDate will be set as End of Life for this image."

New-AzResourceGroupDeployment -TemplateSpecID $id -ResourceGroupName $TemplateSpecRG -versionName $nextPatchVersion -endOfLife $futureDate -sourceVmId $sourceVmId

Write-Output 'Disconnecting AZ Session'
$DisconnectInfo = Disconnect-AzAccount
Write-Output 'End of Job'
