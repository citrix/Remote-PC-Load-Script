#RemotePC import Script RemotePCLoad.ps1
#This script can be used to import computers and user assignments from a CSV file
#and to apply them to a private desktop catalog in Citrix Virtual Apps and Desktops

#Version 1.0 3-18-2020
#Version 1.1 3-19-2020

function Get-ScriptDirectory
{
  $Invocation = (Get-Variable MyInvocation -Scope 1).Value
  Split-Path $Invocation.MyCommand.Path
}

Function LogLine($strLine)
{
	Write-Host $strLine
	$StrTime = Get-Date -Format "MM-dd-yyyy-HH-mm-ss-tt"
	"$StrTime - $strLine " | Out-file -FilePath $LogFile -Encoding ASCII -Append
}


#Script Setup
#===================================================================
$adminAddress = "ddc1.company.com"
#note $adminaddress is ignored when using the cloud sdk
$CatalogName = "RemotePC"
$csvName = "UserMappings.csv"
$AddComputers = $true
$AddUsers = $true
$AllowMultipleUsers = $true
$CheckResultsComputers = $true
$CheckResultsUsers = $true
#===================================================================

$ScriptSource = Get-ScriptDirectory
$ErrorActionPreference = 'stop'
#Create a log folder and file
$LogFolderName = Get-Date -Format "MM-dd-yyyy-HH-mm-tt"
$LogTopFolder = "$ScriptSource\Logs"
If (!(Test-Path "$LogTopFolder"))
{
	mkdir "$LogTopFolder" >$null
}
$LogFolder = "$LogTopFolder\$LogFolderName"
mkdir "$LogFolder" >$null
$LogFile = "$LogFolder\RemotePC_Import_log.txt"

Logline "Running RemotePC Import Script"

$CsvFile = "$ScriptSource\$csvName"
if (Test-Path $CsvFile)
{
	Logline "Found CSV file will import"
	#Get Map csv file
	$MapUsers = Import-Csv -Path $CsvFile -Encoding ASCII
}


#Lets see if the Citrix Broker Admin snapin is loaded and if not load it.
$Snapins =  Get-PSSnapin

foreach ($Snapin in $Snapins) 
{
	If ($Snapin.Name -eq "Citrix.Broker.Admin.V2")
	{
		Logline "Snapin Citrix.Broker.Admin.V2 already loaded!"
		$SnapinLoaded = $True
		break
	}

}

if (!$SnapinLoaded)
{
	Logline "Loading Snapin Citrix.Broker.Admin.V2"
	asnp Citrix*
}

#Now lets make sure it loaded
$SnapinLoaded = $false
$Snapins2 =  Get-PSSnapin

foreach ($Snapin in $Snapins2) 
{
	If ($Snapin.Name -eq "Citrix.Broker.Admin.V2")
	{
		$SnapinLoaded = $True
		break
	}

}
if (!$SnapinLoaded)
{
		Logline "****Snapin [Citrix.Broker.Admin.V2] could not loaded - Exiting Script"
		Throw "Snapin Could not be loaded.  Exiting Script"
		break
}

Try {
	$RemotePCCatalog = Get-BrokerCatalog -AdminAddress $adminAddress -name $CatalogName 
}
Catch {
	Logline "Catalog could not be obtained.  Exiting script"
	Throw "Catalog Could not be loaded.  Exiting Script"
	break
}

if ($AddComputers)
{
	#First Loop through the list and add the computers to the catalog
	Logline "================================================================"
	logline "             Adding Computers to Catalog"
	Logline ""

	foreach ($UserMapping in $MapUsers)
	{

		$Machine = $UserMapping.Computer.Trim()
		$UserName = $UserMapping.UserName.Trim()
		if ($Machine.length -eq 0)
		{
			Logline "**** Machine Name for User [$UserName] is null skipping to next machine"
			continue
		}

		Try {
			Logline "Adding Machine [$machine] to Catalog [$CatalogName]"
			New-BrokerMachine -MachineName $Machine -CatalogUid $RemotePCCatalog.Uid -AdminAddress $adminAddress 
        }
		Catch {
			$ErrorValue = $error[0] 
            if ($ErrorValue -like '*Machine is already allocated')
            {
                Logline "Machine [$machine] has already been added to Catalog [$CatalogName]."
            }
            else
            {
                Logline "=========================================================="
                Logline "**** Adding Machine [$machine] to Catalog [$CatalogName] FAILED"
				Logline $Error[0]
				Logline "=========================================================="
            }
		}
	}

	Start-Sleep 60
} #End AddComputers


if ($AddUsers)
{
	#Now Loop through the list again and assign the users to the computers
	Logline "================================================================"
	logline "             Assigning Users to Computers"
	Logline ""

	foreach ($UserMapping in $MapUsers)
	{
		$Machine = $UserMapping.Computer.Trim()
		$UserName = $UserMapping.UserName.Trim()
		if ($Machine.length -eq 0)
		{
			Logline "+++++ Desktop Name is blank for user [$UserName]. User will not be added"
			continue
		}
        if ($UserName.length -eq 0)
		{
			Logline "+++++ No User Defined for Desktop [$Machine]. User will not be added"
			continue
		}
		$GetDesktop = Get-BrokerPrivateDesktop $Machine -AdminAddress $adminAddress -ErrorAction:SilentlyContinue
		if ($GetDesktop -isnot [Citrix.Broker.Admin.SDK.PrivateDesktop])
		{
			Logline "**** User [$UserName] Desktop [$machine] not found in catalog [$CatalogName]"
			Logline "**** Skipping to next user"
			continue
		}
		
		$GetAssignedUser = Get-BrokerUser -AdminAddress $adminAddress -PrivateDesktopUid $GetDesktop.Uid
		if ($GetAssignedUser.Count -gt 1){$AssignedUserTest = $GetAssignedUser[0]}else{$AssignedUserTest = $GetAssignedUser}
		if ($AssignedUserTest -isnot [Citrix.Broker.Admin.SDK.User])
		{
			#We will assign the user
			Logline "Mapping user [$UserName] to Desktop [$Machine]"
			try {
				Add-BrokerUser -AdminAddress $adminAddress -PrivateDesktop $Machine -Name $UserName
			}
			Catch {
				Logline "=========================================================="
				Logline "Error Adding User [$UserName] to Desktop [$Machine]"
				Logline $Error[0]
				Logline "=========================================================="
			}
			
		}
		elseif ($AllowMultipleUsers)
		{
			[System.Collections.ArrayList]$ArrAssUsers = @()
			foreach ($assUser in $GetAssignedUser)
			{
				$AssignedUser = $assUser.Name
				$ArrAssUsers.Add($AssignedUser)
			}
			
			if ( $ArrAssUsers -notcontains $UserName)
			{
				Logline "Adding additional User [$UserName] to Desktop [$Machine]"
				try {
					Add-BrokerUser -AdminAddress $adminAddress -PrivateDesktop $Machine -Name $UserName
				}
				Catch {
					Logline "=========================================================="
					Logline "Error Adding User [$UserName] to Desktop [$Machine]"
					Logline $Error[0]
					Logline "=========================================================="
				}
			}
		}
		else
		{
			$AssignedUser = $GetAssignedUser.Name
			Logline "+++ User already mapped to Desktop [$Machine] Mapped User [$UserName] Assigned User [$AssignedUser]"
		}
	 
	}
	Start-Sleep 60
} # End AddUsers

#Now Lets Check how we did

$MissingDesktops = "`"UserName`",`"Computer`"`r`n"
$MissingUsers = "`"UserName`",`"Computer`"`r`n"

#Check for Computers
if($CheckResultsComputers)
{
	#Loop through the list and check for the existence of the computers 
	Logline "================================================================"
	logline "             Checking computer assignments"
	Logline ""

	foreach ($UserMapping in $MapUsers)
	{

		$Machine = $UserMapping.Computer.Trim()
		$UserName = $UserMapping.UserName.Trim()
		if ($Machine.length -eq 0)
		{
			Logline "**** Machine Name for User [$UserName] is null skipping to next machine"
			continue
		}
		$GetDesktop = Get-BrokerPrivateDesktop $Machine -AdminAddress $adminAddress -ErrorAction:SilentlyContinue
		if ($GetDesktop -isnot [Citrix.Broker.Admin.SDK.PrivateDesktop])
		{
			Logline "**** User [$UserName] Desktop [$machine] not found in catalog [$CatalogName]"
			Logline "**** Skipping to next user"
			$MissingDesktops += "`"$username`",`"$Machine`"`r`n"
		}
	}
	if ($MissingDesktops -ne "`"UserName`",`"Computer`"`r`n")
	{
		$MissingDesktops | Out-File -LiteralPath "$LogFolder\MissingVDAs.csv" -Encoding ASCII
	}
}

if($CheckResultsUsers)
{
	#Loop through the list and check for the existence of the computers and assignments
	Logline "================================================================"
	logline "             Checking user assignments"
	Logline ""
	foreach ($UserMapping in $MapUsers)
	{
		$Machine = $UserMapping.Computer.Trim()
		$UserName = $UserMapping.UserName.Trim()
		if ($Machine.length -eq 0)
		{
			Logline "**** Machine Name for User [$UserName] is null skipping to next machine"
			continue
		}
		$GetDesktop = Get-BrokerPrivateDesktop $Machine -AdminAddress $adminAddress -ErrorAction:SilentlyContinue
		if ($GetDesktop -isnot [Citrix.Broker.Admin.SDK.PrivateDesktop])
		{
			Logline "**** Desktop [$machine] not found in catalog [$CatalogName] with user User [$UserName]"
			Logline "Therefore this user could not be added.  Will add to the missing list"
			$MissingUsers += "`"$username`",`"$Machine`"`r`n"
			continue
		}
		else
		{
			Logline "Desktop [$machine] found in catalog [$CatalogName]"
		}
		$GetAssignedUser = Get-BrokerUser -AdminAddress $adminAddress -PrivateDesktopUid $GetDesktop.Uid
		if ($GetAssignedUser.Count -gt 1){$AssignedUserTest = $GetAssignedUser[0]}else{$AssignedUserTest = $GetAssignedUser}
		if ($AssignedUserTest -isnot [Citrix.Broker.Admin.SDK.User])
		{
			Logline "Missing user [$UserName] for Desktop [$Machine]"
			$MissingUsers += "`"$username`",`"$Machine`"`r`n"
		}
		elseif ($AllowMultipleUsers)
		{
			[System.Collections.ArrayList]$ArrAssUsers = @()
			foreach ($assUser in $GetAssignedUser)
			{
				$AssignedUser = $assUser.Name
				$ArrAssUsers.Add($AssignedUser)
			}
			
			if ( $ArrAssUsers -notcontains $UserName)
			{
				Logline "Missing user [$UserName] for Desktop [$Machine]"
				$MissingUsers += "`"$username`",`"$Machine`"`r`n"
			}
		}
		else
		{
			Logline "Desktop [$machine] found in catalog [$CatalogName] with user User [$UserName]"
		}
	}
	if ($MissingUsers -ne "`"UserName`",`"Computer`"`r`n")
	{
		$MissingUsers | Out-File -LiteralPath "$LogFolder\MissingUsers.csv" -Encoding ASCII
	}
}
	
