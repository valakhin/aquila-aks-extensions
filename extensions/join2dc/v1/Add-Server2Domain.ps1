
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$DomainName,
	
	[Parameter(Mandatory=$true)]
    [string]$DCIP,

    [Parameter(Mandatory=$true)]
    [string]$DomainUserName,

    [Parameter(Mandatory=$true)]
    [string]$DomainPassword,
	
	[Parameter(Mandatory = $true)]
	[String]
	$AccountName,
	
	[Parameter(Mandatory = $false)]
	[object[]]
	$AdditionalAccounts
	
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'

function ChangeDNS() {
    Write-Host "Changing DNS..."
    Try {
        if ($null -eq $DCIP) {
			Write-Host "No valid $DCIP"
            return $false
        }
        Write-Host "Changing DNS to $DCIP"
        $Adapter = Get-NetAdapter | Where-Object {$_.Name -like "vEthernet (Ethernet*"}
        Set-DnsClientServerAddress -InterfaceIndex ($Adapter).ifIndex -ServerAddresses $DCIP
        return $true
    } catch {
        return $false
    }
}

function JoinDomain() {
    Write-Host "Join to domain..."
    $joinCred = New-Object pscredential -ArgumentList ([pscustomobject]@{
        UserName = $DomainUserName
        Password = (ConvertTo-SecureString -String ($DomainPassword -replace "`n|`r") -AsPlainText -Force)[0]
    })
    Try {
        Add-Computer -Domain $DomainName -Credential $joinCred
		Start-Sleep 10
        return $true
    } catch {
	    Write-Warning Error[0]
		Write-Error $_
        Start-Sleep 10
        return $false
    }

}

function InstallDocker() {
	Write-Host "Installing docker..."
	try {
		Install-Module -Name DockerMsftProvider -Repository PSGallery -Force
		Install-Package -Name docker -ProviderName DockerMsftProvider -Confirm:$False
		return $true
	} catch {
	    Write-Warning Error[0]
		Write-Error $_
	    return $false
	}
}

function InstallRSATADModule()
    {
    try {
	    Add-WindowsFeature RSAT-AD-Powershell;
        Import-Module ActiveDirectory
		Install-Module powershell-yaml -Force
        return $true
    } catch {
        return $false
        }
    }
	
function InstallGMSAAccount($gMSAAcct)
    {
    try {
	    if(Test-ADServiceAccount $gMSAAcct) {
		   return $true
        }		
	    $success = Install-ADServiceAccount $gMSAAcct;
        return $success
    } catch {
        return $false
        }
    }
	
function InstallgMSACRD() {
    # Verify it is already installed or not
	try {
	    Write-Output "Installing GMSA CRD..."
		$crdName = "gmsacredentialspecs.windows.k8s.io"
		$ret = C:\k\kubectl.exe --kubeconfig C:\k\config get CustomResourceDefinition $crdName
		
		# Generate GMSA CRD spec to install on Kubernetes cluster
		$CrdManifestFile = "C:\k\gmsa-crd.yml"
		$resource = [ordered]@{
			"apiVersion" = "apiextensions.k8s.io/v1beta1";
			"kind" = "CustomResourceDefinition";
			"metadata" = @{
				"name" = $crdName
			};
			"spec" = @{
				"group" = "windows.k8s.io";
				"version" = "v1alpha1";
				"names" = @{
					"kind" = "GMSACredentialSpec";
					"plural" = "gmsacredentialspecs"
					};
				"scope" = "Cluster";
				"validation" = @{
				   "openAPIV3Schema" = @{
					  "properties" = @{
						  "credspec" = @{
							"description" = "GMSA Credential Spec";
							"type" = "object"
							}
						}
					  }
					}
			}
		}
		ConvertTo-Yaml $resource | Set-Content $CrdManifestFile
		C:\k\kubectl.exe --kubeconfig C:\k\config apply -f $CrdManifestFile
	} catch {
		Write-Error "The Failed to generate and aplly CRD "
		return $false
	}
}
function GenerateAndApplyCredentialSpec($Domain, $AccountName, $AdditionalAccounts) {
    try {
		# Validate domain information
		$ADDomain = Get-ADDomain -Server $Domain -ErrorAction Continue

		if (-not $ADDomain) {
			Write-Error "The specified Active Directory domain ($Domain) could not be found.`nCheck your network connectivity and domain trust settings to ensure the current user can authenticate to a domain controller in that domain."
			return $false
		}
	   
		# Clean up account names and validate formatting
		$AccountName = $AccountName.TrimEnd('$')

		if ($AdditionalAccounts) {
			$AdditionalAccounts = $AdditionalAccounts | ForEach-Object {
				if ($_ -is [hashtable]) {
					# Check for AccountName and Domain keys
					if (-not $_.AccountName -or -not $_.Domain) {
						Write-Error "Invalid additional account specified: $_`nExpected a samAccountName or a hashtable containing AccountName and Domain keys."
						return $false
					}
					else {

						@{
							AccountName = $_.AccountName.TrimEnd('$')
							Domain = $_.Domain
						}
					}
				}
				elseif ($_ -is [string]) {
					@{
						AccountName = $_.TrimEnd('$')
						Domain = $Domain
					}
				}
				else {
					Write-Error "Invalid additional account specified: $_`nExpected a samAccountName or a hashtable containing AccountName and Domain keys."
					return $false
				}
			}
		}

		#File path to store gMSA credential specification
		$CredSpecRoot = "C:\ProgramData\docker\credentialspecs"
		$FileName = "{0}_{1}" -f $ADDomain.NetBIOSName.ToLower(), $AccountName.ToLower()
		$FullPath = Join-Path $CredSpecRoot "$($FileName.TrimEnd(".json")).json"
	   
		# Start hash table for output
		$output = @{}

		# Create ActiveDirectoryConfig Object
		$output.ActiveDirectoryConfig = @{}
		$output.ActiveDirectoryConfig.GroupManagedServiceAccounts = @( @{"Name" = $AccountName; "Scope" = $ADDomain.DNSRoot } )
		$output.ActiveDirectoryConfig.GroupManagedServiceAccounts += @{"Name" = $AccountName; "Scope" = $ADDomain.NetBIOSName }
		
		#install gMSA account
		Write-Output "Installing $AccountName on host..."
		$ret = InstallGMSAAccount($AccountName)
		if( !$ret) {
		   Write-Output "Faile to install gMSA $AccountName on host..."
		   return $false
		}
		if ($AdditionalAccounts) {
			$AdditionalAccounts | ForEach-Object {
				$output.ActiveDirectoryConfig.GroupManagedServiceAccounts += @{"Name" = $_.AccountName; "Scope" = $_.Domain }
				#install additional gMSA account
				Write-Output "Installing additional gMSA $AccountName on host..."
				$ret = InstallGMSAAccount($_.AccountName)
				if( !$ret ){
				   Write-Output "Faile to install additional gMSA $AccountName on host..."
				   return $false
				}
			}
		}
		
		#create gmsa CRD on cluster
		$ret = InstallgMSACRD
		Start-Sleep 10
		
		# Create CmsPlugins Object
		$output.CmsPlugins = @("ActiveDirectory")

		# Create DomainJoinConfig Object
		$output.DomainJoinConfig = @{}
		$output.DomainJoinConfig.DnsName = $ADDomain.DNSRoot
		$output.DomainJoinConfig.Guid = $ADDomain.ObjectGUID
		$output.DomainJoinConfig.DnsTreeName = $ADDomain.Forest
		$output.DomainJoinConfig.NetBiosName = $ADDomain.NetBIOSName
		$output.DomainJoinConfig.Sid = $ADDomain.DomainSID.Value
		$output.DomainJoinConfig.MachineAccountName = $AccountName

		$output | ConvertTo-Json -Depth 5 | Out-File -FilePath $FullPath -Encoding ascii
		$credSpecContents = Get-Content $FullPath | ConvertFrom-Json
		$ManifestFile = "C:\k\gmsa-cred-spec-$AccountName.yml"
		
		# generate the k8s resource
		$resource = [ordered]@{
			"apiVersion" = "windows.k8s.io/v1alpha1";
			"kind" = 'GMSACredentialSpec';
			"metadata" = @{
			"name" = $AccountName.ToLower()
			};
			"credspec" = $credSpecContents
		}

		ConvertTo-Yaml $resource | Set-Content $ManifestFile

		#Apply gmsa credential spec on Kubernetes cluster
		C:\k\kubectl.exe --kubeconfig C:\k\config apply -f $ManifestFile

		Write-Output "K8S manifest rendered at $ManifestFile"
	} catch {
	    Write-Error "GenerateAndApplyCredentialSpec failed with error $_"
		return $false
	}
}

# Set NIC to look at DC for DNS
$DNSResult = ChangeDNS 

# Join the domain
$JDResult = JoinDomain 

# Install docker
#$IDResult = InstallDocker 

$ret = InstallRSATADModule
if( !$ret ) {
Write-Output "Failed to install RSATADModule"
return
}

$ret = GenerateAndApplyCredentialSpec $DomainName $AccountName $AdditionalAccounts 
if( !$ret ) {
Write-Output "Failed Generate Credential file"
return
}

# Reboot to finish the join
Restart-Computer -Force