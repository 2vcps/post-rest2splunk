#Replace your FlashArrayName (hostname or FQDN) and your username and password.
#This will output several pieces of information about each volume and array.

cls
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
$FlashArrayName = @('pure1','pure2','pure3','pure4')
$AuthAction = @{
    password = "pass"
    username = "user"
}
$pass = cat c:\temp\splunkcred.txt | ConvertTo-SecureString
$myCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "admin",$pass

#Change this value to your price per GB, for doing Chargeback and showback 
$pricePerGB = 0.125 


function post-splunk ($custval,$custval2,$custval3)
{
# url for the splunk with management port default is 8089. Should be the IP, NETBIOS name or FQDN
$url = "192.168.1.218:8089"
#write-host "Enter in the admin account for vCenter Operations"

# prompts for admin credentials for spunk. If running as scheduled task replace with static credentials
$cred = $myCred

#Make sure your time is correct, will make searches in splunk work alot better
$timeStamp = Get-Date

# takes the above values and combines them to set the body for the Http Post request
# these are comma separated.

$body = "$timeStamp,$custval"

# executes the Http Post Request
Invoke-WebRequest -Uri "https://$url/services/receivers/simple?source=$custval3&sourcetype=$custval2" -Credential $cred -Method Post -Body $body

}


#For each FlashArray in the array above
#In the URL after api there is a version number I am using 1.3, depending on your version of Purity this may need to be modified.
ForEach($element in $FlashArrayName)
{
$faName = $element.ToString()
$ApiToken = Invoke-RestMethod -Method Post -Uri "https://${faName}/api/1.3/auth/apitoken" -Body $AuthAction

$SessionAction = @{
    api_token = $ApiToken.api_token
}
Invoke-RestMethod -Method Post -Uri "https://${faName}/api/1.3/auth/session" -Body $SessionAction -SessionVariable Session
 #Get Array level Stats, Array level space stats and finally Volume stats there is a lot more information in the REST API
 #You may be able to customize to pull even more into Splunk
 $PureStats = Invoke-RestMethod -Method Get -Uri "https://${faName}/api/1.3/array?action=monitor" -WebSession $Session
 $PureArray = Invoke-RestMethod -Method Get -Uri "https://${faName}/api/1.3/array?space=true" -WebSession $Session
 $Volumes = Invoke-RestMethod -Method Get -Uri "https://${faName}/api/1.3/volume?space=true" -WebSession $Session


ForEach($Volume in $Volumes) {
    #This inlcudes some math for chargeback each volume would need to map to a customer
    #It calcuates cost based on Provisioned, Host Logicallly written data and Physically written data based on global and volume datareduction
    $dSharedGB = (((($Shared.shared_space/$Volumes.Count)/1024)/1024)/1024)
   
    $volumeGB = ((($volume.volumes/1024)/1024)/1024)
   
    $hostWritten = ($volume.size - ($volume.size * $volume.thin_provisioning))
    
    $hostWrittenGB = ((($hostWritten/1024)/1024)/1024)
    $fairDataReductionVolume = ($hostWrittenGB / $volume.data_reduction)
    $cbFDRV = ($fairDataReductionVolume * $pricePerGB)
    $cbHost = ($hostWrittenGB * $pricePerGB)
    $cbProv = ((((($volume.size)/1024)/1024)/1024) * $pricePerGB)
    
    $Volume | Add-Member -type NoteProperty -name "UniqueVolumeBlocksSizeGBEven" -value $volumeGB -Force
    $Volume | Add-Member -Type NoteProperty -name "GlobalSharedBlocks" -Value $dSharedGB -Force
    $Volume | Add-Member -Type NoteProperty -name "LogicalHost Written" -Value $hostWritten -Force
    $Volume | Add-Member -Type NoteProperty -name "LogicalHostWrittenGB" -Value $hostWrittenGB -Force
    $Volume | Add-Member -Type NoteProperty -name "FairPhysicalSpaceperVolume" -Value $fairDataReductionVolume -Force
    $Volume | Add-Member -Type NoteProperty -Name "ChargeperPhyscialGBPer$" -Value $cbFDRV -Force
    $Volume | Add-Member -Type NoteProperty -Name "ChargeperLogicalHostWritten" -Value $cbHost -Force
    $Volume | Add-Member -Type NoteProperty -Name "ChargeperProvisionedSpace" -Value $cbProv -Force
    $Volume | Add-Member -type NoteProperty -name "arrayname" -value $faName -Force
    $Volume = $Volume  -replace '[@{}]',''
    $Volume = $Volume -replace '[;]',','
    
    post-splunk($Volume)("pure_volstats")($faName)
}

ForEach($FlashArray in $PureStats) {
   
    $FlashArray | Add-Member -Type NoteProperty -name "arrayname" -Value $faName -Force
    $FlashArray = $FlashArray  -replace '[@{}]',''
    $FlashArray = $FlashArray -replace '[;]',',' 
   
    post-splunk($FlashArray)("pure_arraystats")($faName)
    

}
ForEach($FlashArray in $PureArray) {
   $FlashArray | Add-Member -Type NoteProperty -name "arrayname" -Value $faName -Force
   $FlashArray = $FlashArray  -replace '[@{}]',''
   $FlashArray = $FlashArray -replace '[;]',',' 
 
   post-splunk($FlashArray)("pure_arraystats")($faName)
    
    
    

}

 } 