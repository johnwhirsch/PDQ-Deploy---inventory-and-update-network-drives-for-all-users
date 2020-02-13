# PDQ-Deploy---inventory-and-update-network-drives-for-all-users
This script was designed for use with PDQ Deploy to create an inventory and update network drives for all users profiles on a computer.


PDQ Inventory Setup:
1) Go to Options > Scan Profiles
2) Create a new scan profile
3) I named mine "Network Drive Scan"
4) Add a Registry scanner with the following settings:
    a) Hive: HKEY_LOCAL_MACHINE
    b) Include Pattern(s): SOFTWARE\Admin Arsenal\InventoryData\NetworkDrives-\*\\\*
5) Save the new scan profile

PDQ Deploy Setup:
1) Create a CSV file on a network share that your deployment user has access to. See the example CSV: PDQ-NetworkDrives-Replace.csv
2) Update line 2 of the script to point to that CSV file
3) Create a PDQ Deployment to run the Powershell script and paste the code from pdq-inventory-network-drives.ps1 in there
4) Under the script properties 
    a) Set "Scanning" to "Scan After Deployment"
    b) Select the scan profile we just made before
5) Save your deployment and test it on some non-production clients
