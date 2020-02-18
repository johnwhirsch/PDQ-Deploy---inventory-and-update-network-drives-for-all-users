# This share needs to be accessible by the PDQ Deploy user. This file must exist even if it is blank - the script will error out if it doesn't
$replacements = import-csv -Path "Microsoft.PowerShell.Core\FileSystem::\\woodcliff.local\shared\IT$\PDQRepository\PDQNetworkShares.csv" -ErrorAction Continue

# true = Only scan user drives; false = Scan and update drives if they match any of the shares in the $replacements CSV
$scanonly = $true;

# false = Only save drives that don't exist in the replace column of the $replacements CSV
$savealldrives = $true; 

# SilentlyContinue = normal output; Continue = verbose output
$VerbosePreference = "SilentlyContinue"

# Set PDQ Inventory to scan this path to collect all the inventory data as a scan after deployment in PDQ Deploy
$RegPath = "HKLM:\SOFTWARE\Admin Arsenal\InventoryData"

Get-ChildItem -Path $RegPath -ErrorAction SilentlyContinue | ? { $_.Name -match "NetworkDrives" } | Remove-Item

function Get-UsernameFromHivePath {
    param([string]$HivePath)
    return $(select-string -InputObject $HivePath -Pattern '(?!=Users\\)([A-Za-z\s\-_])\w+(?=\\NTuser.dat)' | %{ $_.Matches[0].Groups[0].Value } )
}

function Save-PDQInventory {
    param([string]$Username,[string]$NetworkDrive,[string]$NetworkDrivePath)
    
    try{
        $InventoryLocation = "$($RegPath)\NetworkDrives-$($Username)"

        if($(Test-Path -Path $InventoryLocation) -ne $true){ New-Item -Path $RegPath -Name "NetworkDrives-$($Username)" -Force }
        
        Write-Verbose "Attempting to add to registry: $($NetworkDrive) > $($NetworkDrivePath)`n"

        New-ItemProperty -Path $InventoryLocation -Name $($NetworkDrive) -Value $($NetworkDrivePath) -Force | Out-Null
        
    }catch{ Write-Output "Unable to write inventory to the registry."; exit 666; }

}

try{ $UserProfiles = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\*" | Where {$_.PSChildName -match "S-1-5-21-(\d+-?){4}$" } | Select-Object @{Name="SID"; Expression={$_.PSChildName}}, @{Name="UserHive";Expression={"$($_.ProfileImagePath)\NTuser.dat"}}, @{Name="UserName";Expression={  Get-UsernameFromHivePath -HivePath "$($_.ProfileImagePath)\NTuser.dat"  }} }
catch { Write-Output "Error getting list of user profiles"; Write-Output $error[0].Exception.Message; exit 663; }

Write-Output "Found the following $($UserProfiles.Count) user profiles:"; Write-Output $UserProfiles | FT; Write-Output "`n`n";

# Loop through each profile on the machine
Foreach ($UserProfile in $UserProfiles) {
    # Load User ntuser.dat if it's not already loaded
    If (($ProfileWasLoaded = Test-Path Registry::HKEY_USERS\$($UserProfile.SID)) -eq $false) {
        Write-Verbose "Mounting User Hive: $($UserProfile.UserHive)`n"
        Start-Process -FilePath "CMD.EXE" -ArgumentList "/C REG.EXE LOAD HKU\$($UserProfile.SID) $($UserProfile.UserHive)" -Wait -WindowStyle Hidden
    }

    Write-Verbose "Testing if hive is loaded: $(Test-Path Registry::HKEY_USERS\$($UserProfile.SID))"

    # Get user's network drives
    try{ $RegistryNetworkDrives = Get-Item -Path "Registry::HKEY_USERS\$($UserProfile.SID)\Network\*" -Verbose }
    catch { Write-Output "Error getting information from: $RegistryNetworkDrives"; Write-Output $error[0].Exception.Message; exit 664; }
    
    Write-Output "Getting all user network drives for: $($UserProfile.UserName)"

    if($RegistryNetworkDrives.count -gt 0){
        foreach($RegistryNetworkDrive in $RegistryNetworkDrives){
            try{                

                Write-Verbose "Trying to get drives from: $($RegistryNetworkDrive)\RemotePath`n"

                $NetworkDrive = $(Get-ItemProperty -Path "Registry::$($RegistryNetworkDrive)").PSChildName;
                $NetworkDrivePath = Get-ItemPropertyValue -Path "Registry::$($RegistryNetworkDrive)" -Name "RemotePath"
                $NetworkDriveCorrect = $true;

                Write-Output "Found Network Drive For $($UserProfile.UserName) - $($NetworkDrive): $($NetworkDrivePath)";

                try{ 
                    #Only run this if you want to scan & update the network drives
                    if($scanonly -eq $false){
                        foreach($replacement in $replacements){ 
                            if($NetworkDrivePath -like "*$($replacement.find)*"){
                                
                                #Delete any drives with the replacement value of "DELETE" in the replacement CSV
                                if($replacement.replace -eq "DELETE"){ Remove-Item -Path Registry::$($RegistryNetworkDrive) -Force; Write-Output "Found network drive to delete: $($replacement.find)" }
                                else{
                                    #Replace the matching portion of the old network drive with it's replacement value from the CSV
                                    $NetworkDrivePath = $($NetworkDrivePath -replace [regex]::Escape($($replacement.find)),$($replacement.replace)); 
                                    New-ItemProperty -Path "Registry::$($RegistryNetworkDrive)" -Name "RemotePath" -Value $($NetworkDrivePath) -Force
                                    Write-Output "Updating Network Drive For $($UserProfile.UserName) - $($NetworkDrive): $($NetworkDrivePath)"
                                }

                            }
                        }
                    }
                }catch{  Write-Output "Error converting the network drive path"; Write-Output $error[0].Exception.Message; exit 665; }

                if($savealldrives -eq $false){
                    #Add the network drive to the PDQ inventory if it doesn't match one of the replacement drives; else save all network drives to PDQ inventory
                    $foundReplacement = $false; foreach($replacement in $replacements){  if($NetworkDrivePath -like "*$($replacement.replace)*"){ $foundReplacement=$true }  } 
                    if($foundReplacement -eq $false){ Save-PDQInventory -Username $($UserProfile.UserName) -NetworkDrive $($NetworkDrive) -NetworkDrivePath $($NetworkDrivePath) }
                }else{ Save-PDQInventory -Username $($UserProfile.UserName) -NetworkDrive $($NetworkDrive) -NetworkDrivePath $($NetworkDrivePath) }

            }catch{ Write-Output "Error getting information from: $RegistryNetworkDrives"; Write-Output $error[0].Exception.Message; exit 667; }
        }
    }

    # Unload NTuser.dat        
    If ($ProfileWasLoaded -eq $false) {
        [gc]::Collect()
        Start-Sleep 1
        Start-Process -FilePath "CMD.EXE" -ArgumentList "/C REG.EXE UNLOAD HKU\$($UserProfile.SID)" -Wait -WindowStyle Hidden| Out-Null
    }
}
