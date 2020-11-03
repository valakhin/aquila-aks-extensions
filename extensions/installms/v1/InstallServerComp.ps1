
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
	
	[Parameter(Mandatory=$true)]
    [string]$MgName,

    [Parameter(Mandatory=$true)]
    [string]$SqlInstance,
	
	[Parameter(Mandatory = $true)]
	[String]$AccountName,
	
	[Parameter(Mandatory = $false)]
	[String]$ProdVersion,
	
	[Parameter(Mandatory = $false)]
	[object[]]$AdditionalAccounts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'
		
function InstallgMSACRD() {
    # Verify it is already installed or not
	try {
	    Write-Output "Installing GMSA CRD..."
		$crdName = "gmsacredentialspecs.windows.k8s.io"
		
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
		#Apply the CustomResourceDefinition for gMSA
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
		
		if ($AdditionalAccounts) {
			$AdditionalAccounts | ForEach-Object {
				$output.ActiveDirectoryConfig.GroupManagedServiceAccounts += @{"Name" = $_.AccountName; "Scope" = $_.Domain }
			}
		}
		

		
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

function BuildManagementServerContainer($DomainName, $AccountName, $MgName, $SqlInstance, $ProdVersion) {
	#download install script and dockerfile
	$url = "https://raw.githubusercontent.com/valakhin/aquila-aks-extensions/master/extensions/installms/v1"

	mkdir Docker
	Invoke-WebRequest -UseBasicParsing $url/Build-Container4MS.ps1 -OutFile Build-Container4MS.ps1 
	Invoke-WebRequest -UseBasicParsing $url/Docker/Dockerfile -OutFile Docker/Dockerfile 
	Invoke-WebRequest -UseBasicParsing $url/Docker/Start.ps1 -OutFile Docker/Start.ps1 
	Invoke-WebRequest -UseBasicParsing $url/Docker/wait4setupcomplete.ps1 -OutFile Docker/wait4setupcomplete.ps1 

	./Build-Container4MS $DomainName $AccountName $MgName $SqlInstance $ProdVersion

}

#create gmsa CRD on cluster
$ret = InstallgMSACRD
Start-Sleep 10

$ret = GenerateAndApplyCredentialSpec $DomainName $AccountName $AdditionalAccounts 
if( !$ret ) {
Write-Output "Failed Generate Credential file"
return
}


BuildManagementServerContainer $DomainName $AccountName $MgName $SqlInstance $ProdVersion

# Reboot to finish the join
Restart-Computer -Force