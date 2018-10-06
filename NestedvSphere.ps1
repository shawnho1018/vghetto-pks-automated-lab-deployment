### This file is to deploy Nested Hypervisor ###
Import-Module -Name ./functions.psm1 -Verbose
$config = Get-Content ./Nested-Parameters.json | Out-String | ConvertFrom-Json
### Test Variables ###
if(!(Test-Path $config.vSphere_Deployment.NestedESXiResources.FilePath)) {
    Write-Host -ForegroundColor Red "`nUnable to find $($config.vSphere_Deployment.NestedESXiResources.FilePath) ...`nexiting"
    exit
}
if (!(Test-Path $config.vSphere_Deployment.NewVCSA.FilePath)){
    Write-Host -ForegroundColor Red "Unable to find $($config.vSphere_Deployment.NewVCSA.FilePath)"
}
My-Logger "Connecting to Existing vCenter"
$viConnection = Connect-VIServer -Server $config.ExistingVC.IPAddress -User $config.ExistingVC.Username -Password $config.ExistingVC.Password
