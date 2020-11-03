[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$DomainName,
	
	[Parameter(Mandatory = $true)]
	[String]$AccountName,
	
	[Parameter(Mandatory=$true)]
    [string]$mgName,

    [Parameter(Mandatory=$true)]
    [string]$sqlInstance,
	
	[Parameter(Mandatory=$false)]
    [string]$prodVersion
	
)
$passwd="CtqiR2lJ8IIh60ggDmOKw2K0Rwc+Hr6n" 

#Login to Aquila ACR
#ignore login warning 
try {
	#docker login -u aquila -p CtqiR2lJ8IIh60ggDmOKw2K0Rwc+Hr6n aquila.azurecr.io
	echo $passwd | docker login -u aquila --password-stdin aquila.azurecr.io
	Write-Output "Container registry login Success"
} catch {
	Write-Output "Container registry login Failed"
}

if (-not $prodVersion) {
	$prodVersion='latest'
}

#pull image for SCOM setup
docker pull aquila.azurecr.io/scommisetupmain:$prodVersion

$dbname = "OperationsManager$mgName"
$dwname = "OperationsManagerDW$mgName"

$CredFileName = "{0}_{1}.json" -f $DomainName.Split('.')[0].ToLower(), $AccountName.ToLower()

$ImageName = "scomserver{0}:{1}" -f $mgName.ToLower(), $prodVersion.ToLower()

# build docker image for SCOM management server
# It will install SCOM management server components
docker build --security-opt "credentialspec=file://$CredFileName" --build-arg components=OMServer `
             --build-arg domainFQDN=$DomainName --build-arg gMSAService=$AccountName `
			 --build-arg sqlserverinstance=$sqlInstance --build-arg dbname=$dbname `
			 --build-arg dwname=$dwname --build-arg mgName=$mgName -t $ImageName  Docker/

# tag the build image and push to container registry
docker tag $ImageName aquila.azurecr.io/$ImageName
docker push aquila.azurecr.io/$ImageName

