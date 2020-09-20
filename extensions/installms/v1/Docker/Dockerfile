# Base image - windows server core
FROM aquila.azurecr.io/scommisetupmain:latest
LABEL maintainer "Aquila team"

ARG components="OMServer"
ARG mgName=""
ARG domainFQDN="" 
ARG gMSAService=""
ARG sqlserverinstance="" 
ARG dbname="OperationsManager" 
ARG dwname="OperationsManagerDW" 
ARG serviceaccount=""

ENV components=${components}  \
    mgName=${mgName} \
    domainFQDN=${domainFQDN}  \
	gMSAService=${gMSAService} \
    sqlserverinstance=${sqlserverinstance}  \
    dbname=${dbname} \
    dwname=${dwname} \
    serviceaccount=${serviceaccount}


# SCOM management server has 3 services are running in it (Health service, SDK service and configuration service)
# Health service and SDK service are been exposed with 5723 and 5724 ports
EXPOSE 5723 5724
    
SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

COPY ./ ./
WORKDIR /
   
RUN net localgroup administrators "$env:domainFQDN\$env:gMSAService$" /add
RUN net localgroup administrators "$env:domainFQDN\sqladmin" /add
RUN Write-Output (\"{0} {1}.{2} {1}\" -f \"127.0.0.1\", "$env:gMSAService", "$env:domainFQDN") > "C:\Windows\System32\drivers\etc\hosts" ; \
   Get-Content "C:\Windows\System32\drivers\etc\hosts"


# Place this Docker file at where SCOM setup files been downloaded, installables in "Main" folder
# copy setup files to container context

RUN .\Main\Setup.exe /install /silent /Components:$env:components /SendCEIPReports:0 /EnableErrorReporting:Never \
/UseMicrosoftUpdate:0 /AcceptEndUserLicenseAgreement:1 /DatabaseSize:8000 /ManagementgroupName:$env:mgName \
/SqlServerInstance:$env:sqlserverinstance /DatabaseName:$env:dbname \
/DWSqlServerInstance:$env:sqlserverinstance /DWDatabaseName:$env:dwname \
/UseLocalSystemDataWriterAccount /UseLocalSystemDataReaderAccount /UseLocalSystemActionAccount /UseLocalSystemDASAccount; \
     Start-Sleep -s 60; \
	 Write-Host "SCOM installation in progress, wait for it to finish" ; \
	 .\wait4setupcomplete.ps1 ; \
	 Write-Host "SCOM installation Completed" ; \
	 Get-Content "~\AppData\Local\SCOM\Logs\OpsMgrSetupWizard.log" ;

CMD .\start -Verbose



