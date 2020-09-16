
while ($true) 
{ 
    $setupcomplete = (Get-content   ~\AppData\Local\SCOM\LOGS\Setup0.log -Tail 10 -Encoding Unicode | Select-String -pattern 'LaunchExeAndWait : Finished')
	if ($setupcomplete) { 
	    Write-Output "Completed SCOM installation" 
		break
	}
    Start-Sleep -Seconds 60 
}
#Verify the setup is succssful or failed
$setupcomplete = (Get-content   ~\AppData\Local\SCOM\LOGS\Setup0.log -Tail 10 -Encoding Unicode | Select-String -pattern 'CommonWinMain : Successful')
if ($setupcomplete) { 
	Write-Output "Completed SCOM installation successfully"
	
} else { 
	Write-Output "SCOM installation Failed"
}