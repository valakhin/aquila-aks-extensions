
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$DomainName,
	
	[Parameter(Mandatory=$true)]
    [string]$DCIP,

    [Parameter(Mandatory=$true)]
    [string]$DomainUserName,

    [Parameter(Mandatory=$true)]
    [string]$DomainPassword
	
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
        $Adapter = Get-NetAdapter | Where-Object {$_.Name -like "Ethernet"}
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
		Install-Package -Name docker -ProviderName DockerMsftProvider
		return $true
	} catch {
	    Write-Warning Error[0]
		Write-Error $_
	    return $false
	}
}

# Set NIC to look at DC for DNS
$DNSResult = ChangeDNS 

# Join the domain
$JDResult = JoinDomain 

# Install docker
$IDResult = InstallDocker 

# Reboot to finish the join
Restart-Computer -Force