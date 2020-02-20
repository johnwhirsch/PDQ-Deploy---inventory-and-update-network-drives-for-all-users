# This share needs to be accessible by the PDQ Deploy user. This file must exist even if it is blank - the script will error out if it doesn't
$ShareReplacements = import-csv -Path "D:\Users\johhir\Desktop\PDQNetworkShares.csv" -ErrorAction Continue
$PrinterReplacements = import-csv -Path "D:\Users\johhir\Desktop\PDQNetworkPrinters.csv" -ErrorAction Continue

# true = Only scan user drives; false = Scan and update drives if they match any of the shares in the $ShareReplacements CSV
$scanonly = $true;

# false = Only save drives that don't exist in the replace column of the $ShareReplacements CSV
$savealldrives = $false; 
$saveallprinters = $false;

# SilentlyContinue = normal output; Continue = verbose output
$VerbosePreference = "SilentlyContinue"

# Set PDQ Inventory to scan this path to collect all the inventory data as a scan after deployment in PDQ Deploy
$RegPath = "HKLM:\SOFTWARE\Admin Arsenal\InventoryData"

Get-ChildItem -Path $RegPath -ErrorAction SilentlyContinue | ? { $_.Name -match "NetworkDrives" -or $_.Name -match "NetworkPrinters" } | Remove-Item

function Get-UsernameFromHivePath {
    param([Parameter(Mandatory=$True)][string]$HivePath)
    return $(select-string -InputObject $HivePath -Pattern '(?!=Users\\)([A-Za-z\s\-_])\w+(?=\\NTuser.dat)' | %{ $_.Matches[0].Groups[0].Value } )
}

function Save-PDQNetworkInventory {
    param([Parameter(Mandatory=$True)][string]$Username,[Parameter(Mandatory=$True)][string]$NetworkDrive,[Parameter(Mandatory=$True)][string]$NetworkDrivePath)
    
    try{
        $InventoryLocation = "$($RegPath)\NetworkDrives-$($Username)"

        if($(Test-Path -Path $InventoryLocation) -ne $true){ New-Item -Path $RegPath -Name "NetworkDrives-$($Username)" -Force | Out-Null }
        
        Write-Verbose "Attempting to add to registry: $($NetworkDrive) > $($NetworkDrivePath)`n"

        New-ItemProperty -Path $InventoryLocation -Name $($NetworkDrive) -Value $($NetworkDrivePath) -Force | Out-Null
        
    }catch{ Write-Output "Unable to write share inventory to the registry."; exit 666; }

}

function Save-PDQPrinterInventory {
    param([Parameter(Mandatory=$True)][string]$Username,[Parameter(Mandatory=$True)][string]$PrinterName,[Parameter(Mandatory=$True)][string]$ServerName)
    

    try{
        $InventoryLocation = "$($RegPath)\NetworkPrinters-$($Username)"

        if($(Test-Path -Path $InventoryLocation) -ne $true){ New-Item -Path $RegPath -Name "NetworkPrinters-$($Username)" -Force | Out-Null }
        
        Write-Verbose "Attempting to add to registry: $($Server) > $($PrinterName)`n"

        New-ItemProperty -Path $InventoryLocation -Name $($PrinterName) -Value $($ServerName) -Force | Out-Null
        
    }catch{ Write-Output "Unable to write printer inventory to the registry."; exit 666; }

}

function Find-Replace {
    param([Parameter(Mandatory=$True)][string]$InputString,[Parameter(Mandatory=$True)][Object[]]$Replacements)
    foreach($replacement in $Replacements){ 
        if($InputString -like "*$($replacement.find)*"){ 
            if($replacement.Replace-eq "DELETE"){ $InputString = "DELETE" }
            else{ $InputString = $($InputString -replace [regex]::Escape($($Replacement.Find)),$($Replacement.Replace)); }
        }
    }
    return $InputString
}

function Get-UserNetworkDrives {

    param([Parameter(Mandatory=$True)][Object[]]$RegistryNetworkDrives)
    
    foreach($RegistryNetworkDrive in $RegistryNetworkDrives){
        try{                

            Write-Verbose "Trying to get drives from: $($RegistryNetworkDrive)\RemotePath`n"

            $NetworkDrive = $(Get-ItemProperty -Path "Registry::$($RegistryNetworkDrive)").PSChildName;
            $NetworkDrivePath = Get-ItemPropertyValue -Path "Registry::$($RegistryNetworkDrive)" -Name "RemotePath"
            $NetworkDriveDeleted = $false;

            Write-Output "Found Network Drive For $($UserProfile.UserName) - $($NetworkDrive): $($NetworkDrivePath)";

            try{ 
                #Only run this if you want to scan & update the network drives
                if($scanonly -eq $false){
                    
                    #Delete any drives with the replacement value of "DELETE" in the replacement CSV
                    if($(Find-Replace -InputString $NetworkDrivePath -Replacements $ShareReplacements) -eq "DELETE"){ 
                        Remove-Item -Path Registry::$($RegistryNetworkDrive) -Force; 
                        $NetworkDriveDeleted = $True;
                        Write-Output "Found network drive to delete: $($replacement.find)" 
                    }
                    if($(Find-Replace -InputString $NetworkDrivePath -Replacements $ShareReplacements) -ne $NetworkDrivePath){
                     
                        #Replace the matching portion of the old network drive with it's replacement value from the CSV
                        $NetworkDrivePath = $(Find-Replace -InputString $NetworkDrivePath -Replacements $ShareReplacements) 
                        New-ItemProperty -Path "Registry::$($RegistryNetworkDrive)" -Name "RemotePath" -Value $($NetworkDrivePath) -Force
                        Write-Output "Updating Network Drive For $($UserProfile.UserName) - $($NetworkDrive): $($NetworkDrivePath)"
                    }                    
                }
            }catch{  Write-Output "Error converting the network drive path"; Write-Output $error[0].Exception.Message; exit 665; }

            if($savealldrives -eq $false -and $NetworkDriveDeleted -eq $false){
                #Add the network drive to the PDQ inventory if it doesn't match one of the replacement drives; else save all network drives to PDQ inventory
                $foundReplacement = $false; foreach($replacement in $ShareReplacements){  if($NetworkDrivePath -like "*$($replacement.replace)*"){ $foundReplacement=$true }  } 
                if($foundReplacement -eq $false){ Save-PDQNetworkInventory -Username $($UserProfile.UserName) -NetworkDrive $($NetworkDrive) -NetworkDrivePath $($NetworkDrivePath) }
            }
            if($savealldrives -eq $True -and $NetworkDriveDeleted -eq $false){ Save-PDQNetworkInventory -Username $($UserProfile.UserName) -NetworkDrive $($NetworkDrive) -NetworkDrivePath $($NetworkDrivePath) }

        }catch{ Write-Output "Error getting information from: $RegistryNetworkDrives"; Write-Output $error[0].Exception.Message; exit 667; }
    }
}

function Get-UserNetworkPrinters {

    param([Parameter(Mandatory=$True)][Object[]]$RegistryNetworkPrinters)

    foreach($RegistryNetworkPrinter in $RegistryNetworkPrinters){
        try{                

            Write-Verbose "Trying to get printers from: $($RegistryNetworkPrinter)`n"

            $NetworkPrinterConnection = $(Get-ItemProperty -Path "Registry::$($RegistryNetworkPrinter)").PSChildName;                                    
            $NetworkPrinterName = $($NetworkPrinterConnection -split ",")[-1]
            $NetworkPrinterServer = $(Get-ItemPropertyValue -Path "Registry::$($RegistryNetworkPrinter)" -Name "Server");
            $NetworkPrinterDeleted = $false;

            Write-Output "Found Network Printer For $($UserProfile.UserName) - $($NetworkPrinterServer)\$($NetworkPrinterName)";
            
            try{ 
                #Only run this if you want to scan & update the network drives
                if($scanonly -eq $false){
                                
                    #Delete any printers with the replacement value of "DELETE" in the replacement CSV
                    if($(Find-Replace -InputString $NetworkPrinterConnection -Replacements $PrinterReplacements) -eq "DELETE"){ 
                        Remove-Item -Path Registry::$($RegistryNetworkPrinter) -Force; 
                        $NetworkPrinterDeleted = $True;
                        Write-Output "Found network printer for $($UserProfile.UserName) to delete: $($NetworkPrinterName)" 
                    }
                    if($(Find-Replace -InputString $NetworkPrinterConnection -Replacements $PrinterReplacements) -ne $NetworkPrinterConnection){                                                                 
                    
                        $NetworkPrinterConnection = $(Find-Replace -InputString $NetworkPrinterConnection -Replacements $PrinterReplacements)
                        $NetworkPrinterName = $(Find-Replace -InputString $NetworkPrinterName -Replacements $PrinterReplacements)                             
                        $NetworkPrinterServer = $(Find-Replace -InputString $NetworkPrinterServer -Replacements $PrinterReplacements)

                        Write-Output "Updating Network Printer For $($UserProfile.UserName) - $($NetworkPrinterServer)\$($NetworkPrinterName)"

                        New-ItemProperty -Path "Registry::$($RegistryNetworkPrinter)" -Name "Server" -Value "$($NetworkPrinterServer)" -Force

                        Rename-Item -Path "$($RegistryNetworkPrinter.PSPath)" -NewName $NetworkPrinterConnection -Force

                    } #end if recursive replace doesn't match the original string
                } #end if scanonly equals false
            }catch{  Write-Output "Error converting the network printer path"; Write-Output $error[0].Exception.Message; exit 665; }
            
            if($saveallprinters -eq $false -and $NetworkPrinterDeleted -eq $false){
                #Add the network drive to the PDQ inventory if it doesn't match one of the replacement drives; else save all network drives to PDQ inventory
                $foundReplacement = $false; foreach($replacement in $PrinterReplacements){  if($NetworkPrinterServer -like "*$($replacement.replace)*"){ $foundReplacement=$true }  } 
                if($foundReplacement -eq $false){ Save-PDQPrinterInventory -Username $($UserProfile.UserName) -PrinterName $NetworkPrinterName -ServerName $NetworkPrinterServer }
            }
            if($saveallprinters -eq $true -and $NetworkPrinterDeleted -eq $false){ Save-PDQPrinterInventory -Username $($UserProfile.UserName) -PrinterName $NetworkPrinterName -ServerName $NetworkPrinterServer }

        }catch{ Write-Output "Error getting network printer information from: $RegistryNetworkPrinter"; Write-Output $error[0].Exception.Message; exit 667; }
    }

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
    Write-Output "----------------------------------------------------------------"
    Write-Output "Getting all user network drives for: $($UserProfile.UserName)"
    try{ $RegistryNetworkDrives = Get-Item -Path "Registry::HKEY_USERS\$($UserProfile.SID)\Network\*" }
    catch { Write-Output "Error getting network drive information from: $RegistryNetworkDrives"; Write-Output $error[0].Exception.Message; exit 664; }

    # Get user's network printers
    Write-Output "Getting all user network printers for: $($UserProfile.UserName)"
    try{ $RegistryNetworkPrinters = Get-Item -Path "Registry::HKEY_USERS\$($UserProfile.SID)\Printers\Connections\*" }
    catch { Write-Output "Error getting network printer information from: $RegistryNetworkPrinters"; Write-Output $error[0].Exception.Message; exit 664; }
        
    if($RegistryNetworkDrives.count -gt 0){ Get-UserNetworkDrives -RegistryNetworkDrives $RegistryNetworkDrives }

    if($RegistryNetworkPrinters.count -gt 0){ Get-UserNetworkPrinters -RegistryNetworkPrinters $RegistryNetworkPrinters }

    Write-Output "----------------------------------------------------------------`n`n"
    # Unload NTuser.dat        
    If ($ProfileWasLoaded -eq $false) {
        [gc]::Collect()
        Start-Sleep 1
        Start-Process -FilePath "CMD.EXE" -ArgumentList "/C REG.EXE UNLOAD HKU\$($UserProfile.SID)" -Wait -WindowStyle Hidden| Out-Null
    }
}
