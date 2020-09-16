[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$DomainName,
	
	[Parameter(Mandatory = $true)]
	[String]$AccountName,
	
	[Parameter(Mandatory=$true)]
    [string]$mgName,

    [Parameter(Mandatory=$true)]
    [string]$sqlInstance
)

#Login to Aquila ACR
docker login -u aquila -p CtqiR2lJ8IIh60ggDmOKw2K0Rwc+Hr6n aquila.azurecr.io

#pull image for SCOM setup
docker pull aquila.azurecr.io/scommisetupmain:latest

$dbname = "OperationsManager$mgName"
$dwname = "OperationsManagerDW$mgName"

$CredFileName = "{0}_{1}.json" -f $DomainName.Split('.')[0].ToLower(), $AccountName.ToLower()

# build docker image for SCOM management server
# It will install SCOM management server components
docker build --security-opt "credentialspec=file://$CredFileName" --build-arg components=OMServer `
             --build-arg domainFQDN=$DomainName --build-arg gMSAService=$AccountName `
			 --build-arg sqlserverinstance=$sqlInstance --build-arg dbname=$dbname `
			 --build-arg dwname=$dwname --build-arg mgName=$mgName -t scomservermain:latest  Docker/

# tag the build image and push to container registry
docker tag scomservermain:latest aquila.azurecr.io/scomservermain:latest
docker push aquila.azurecr.io/scomservermain:latest

