### This script is to deploy NSX-T on Nested vSphere Environment
Import-Module -Name ./functions.psm1 -Verbose
$config = Get-Content ./Nested-Parameters.json | Out-String | ConvertFrom-Json
$verboseLogFile = "./shawn-nsxt-debug.log"

### List Parameters for User Confirmation ###
Write-Host -ForegroundColor Magenta "`nPlease confirm the following configuration will be deployed:`n"
Write-Host -ForegroundColor Yellow "---- Shawnho NSX-T Automated Lab Deployment Configuration ---- "

if($DeployNSX -eq 1) {
    Write-Host -NoNewline -ForegroundColor Green "NSX-T Manager Image Path: "
    Write-Host -ForegroundColor White $config.NSXT_Deployment.NewNSXTMgr.FilePath
    Write-Host -NoNewline -ForegroundColor Green "NSX-T Controller Image Path: "
    Write-Host -ForegroundColor White $config.NSXT_Deployment.NewNSXController.FilePath
    Write-Host -NoNewline -ForegroundColor Green "NSX-T Edge Image Path: "
    Write-Host -ForegroundColor White $config.NSXT_Deployment.NewNSXEdge.FilePath
    Write-Host -NoNewline -ForegroundColor Green "NSX-T Private VM Network: "
    Write-Host -ForegroundColor White $config.NSXT_Deployment.DeployTo.privateNetwork
}    
Write-Host -NoNewline -ForegroundColor Green "VM Storage: "
Write-Host -ForegroundColor White $config.NSXT_Deployment.DeployTo.Datastore
Write-Host -NoNewline -ForegroundColor Green "VM Cluster: "
Write-Host -ForegroundColor White $config.NSXT_Deployment.DeployTo.Cluster
if($DeployNSX -eq 1) {
    Write-Host -ForegroundColor Yellow "`n---- NSX-T Configuration ----"
    Write-Host -NoNewline -ForegroundColor Green "NSX Manager Hostname: "
    Write-Host -ForegroundColor White $config.NSXT_Deployment.NewNSXTMgr.Name
    Write-Host -NoNewline -ForegroundColor Green "NSX Manager IP Address: "
    Write-Host -ForegroundColor White $config.NSXT_Deployment.NewNSXTMgr.IPAddress
    Write-Host -NoNewline -ForegroundColor Green "# of NSX Controller VMs: "
    Write-Host -ForegroundColor White $config.NSXT_Deployment.NewNSXTController.ControllerIPs.Count
    Write-Host -NoNewline -ForegroundColor Green "IP Address(s): "
    Write-Host -ForegroundColor White $config.NSXT_Deployment.NewNSXTController.ControllerIPs
    Write-Host -NoNewline -ForegroundColor Green "# of NSX Edge VMs: "
    Write-Host -ForegroundColor White $config.NSXT_Deployment.NewNSXTEdge.EdgeIPs.Count
    Write-Host -NoNewline -ForegroundColor Green "IP Address(s): "
    Write-Host -ForegroundColor White $config.NSXT_Deployment.NewNSXTEdge.EdgeIPs
    Write-Host -NoNewline -ForegroundColor Green "Netmask: "
    Write-Host -ForegroundColor White $config.NSXT_Deployment.DeployTo.NetMask
    Write-Host -NoNewline -ForegroundColor Green "Gateway: "
    Write-Host -ForegroundColor White $config.NSXT_Deployment.DeployTo.Gateway
    Write-Host -NoNewline -ForegroundColor Green "Enable SSH: "
    Write-Host -ForegroundColor White $config.NSXT_Deployment.NewNSXTMgr.SSHEnable
    Write-Host -NoNewline -ForegroundColor Green "Enable Root Login: "
    Write-Host -ForegroundColor White $config.NSXT_Deployment.NewNSXTMgr.SSHEnableRootLogin
}   

$nsxTotalCPU += $config.NSXT_Deployment.NewNSXTController.ControllerIPs.Count * [int]$config.NSXT_Deployment.NewNSXTController.vCPU
$nsxTotalMemory += $config.NSXT_Deployment.NewNSXTController.ControllerIPs.Count * [int]$config.NSXT_Deployment.NewNSXTController.vCPU
$nsxTotalStorage += $config.NSXT_Deployment.NewNSXTController.ControllerIPs.Count * [int]$config.NSXT_Deployment.NewNSXTController.disk

$nsxTotalCPU += [int]$config.NSXT_Deployment.NewNSXTMgr.vCPU
$nsxTotalMemory += [int]$config.NSXT_Deployment.NewNSXTMgr.vMEM
$nsxTotalStorage += [int]$config.NSXT_Deployment.NewNSXTMgr.disk

$nsxTotalCPU += $config.NSXT_Deployment.NewNSXTEdge.EdgeIPs.Count * [int]$config.NSXT_Deployment.NewNSXTMgr.vCPU
$nsxTotalMemory +=  $config.NSXT_Deployment.NewNSXTEdge.EdgeIPs.Count * [int]$config.NSXT_Deployment.NewNSXTMgr.vMEM
$nsxTotalStorage +=  $config.NSXT_Deployment.NewNSXTEdge.EdgeIPs.Count * [int]$config.NSXT_Deployment.NewNSXTMgr.disk

Write-Host -NoNewline -ForegroundColor Green "NSX VM CPU: "
Write-Host -NoNewline -ForegroundColor White $nsxTotalCPU
Write-Host -NoNewline -ForegroundColor Green " NSX VM Memory: "
Write-Host -NoNewline -ForegroundColor White $nsxTotalMemory "GB "
Write-Host -NoNewline -ForegroundColor Green " NSX VM Storage: "
Write-Host -ForegroundColor White $nsxTotalStorage "GB"
   
Write-Host -ForegroundColor Magenta "`nWould you like to proceed with this deployment?`n"
$answer = Read-Host -Prompt "Do you accept (Y or N)"
if($answer -ne "Y" -or $answer -ne "y") {
    exit
}
Clear-Host
### Connect to vCenter ###
My-Logger "Connecting to Management vCenter Server $($config.ExistingVC.Hostname) ..."
$viConnection = Connect-VIServer $config.ExistingVC.Hostname -User $config.ExistingVC.Username -Password $config.ExistingVC.Password -WarningAction SilentlyContinue
### Retrieve all parameters ###
$datastore = Get-Datastore -Server $viConnection -Name $config.NSXT_Deployment.DeployTo.Datastore | Select-Object -First 1
### This script only works with vDS
$network = Get-VDPortgroup -Server $viConnection -Name $config.NSXT_Deployment.DeployTo.VMNetwork | Select-Object -First 1

$privateNetwork = Get-VDPortgroup -Server $viConnection -Name $config.NSXT_Deployment.DeployTo.privateNetwork | Select -First 1
$NSXIntermediateNetwork = Get-VDPortgroup -Server $viConnection -Name $config.NSXT_Deployment.DeployTo.VMNetwork | Select -First 1

$cluster = Get-Cluster -Server $viConnection -Name $config.NSXT_Deployment.DeployTo.Cluster
$datacenter = $cluster | Get-Datacenter
$vmhost = $cluster | Get-VMHost | Select-Object -First 1

### Deploy NSX-T ###
### Start with NSX-T Manager ###
$nsxMgrOvfConfig = Get-OvfConfiguration $config.NSXT_Deployment.NewNSXTMgr.FilePath
$nsxMgrOvfConfig.DeploymentOption.Value = $config.NSXT_Deployment.NewNSXTMgr.size
$nsxMgrOvfConfig.NetworkMapping.Network_1.value = $config.NSXT_Deployment.DeployTo.VMNetwork

$nsxMgrOvfConfig.Common.nsx_role.Value = "nsx-manager"
$nsxMgrOvfConfig.Common.nsx_hostname.Value = $config.NSXT_Deployment.NewNSXTMgr.hostname
$nsxMgrOvfConfig.Common.nsx_ip_0.Value = $config.NSXT_Deployment.NewNSXTMgr.IPAddress
$nsxMgrOvfConfig.Common.nsx_netmask_0.Value = $config.NSXT_Deployment.DeployTo.NetMask
$nsxMgrOvfConfig.Common.nsx_gateway_0.Value = $config.NSXT_Deployment.DeployTo.Gateway
$nsxMgrOvfConfig.Common.nsx_dns1_0.Value = $config.NSXT_Deployment.DeployTo.DNS
$nsxMgrOvfConfig.Common.nsx_domain_0.Value = $config.NSXT_Deployment.DeployTo.VMDomain
$nsxMgrOvfConfig.Common.nsx_ntp_0.Value = $config.NSXT_Deployment.DeployTo.NTP
if($config.NSXT_Deployment.NewNSXTMgr.SSHEnable -eq "true") {
    $NSXSSHEnableVar = $true
} else {
    $NSXSSHEnableVar = $false
}
$nsxMgrOvfConfig.Common.nsx_isSSHEnabled.Value = $NSXSSHEnableVar
if($config.NSXT_Deployment.NewNSXTMgr.SSHEnableRootLogin -eq "true") {
    $NSXRootPasswordVar = $true
} else {
    $NSXRootPasswordVar = $false
}
$nsxMgrOvfConfig.Common.nsx_allowSSHRootLogin.Value = $NSXRootPasswordVar

$nsxMgrOvfConfig.Common.nsx_passwd_0.Value = $config.NSXT_Deployment.NewNSXTMgr.RootPassword
$nsxMgrOvfConfig.Common.nsx_cli_username.Value = $config.NSXT_Deployment.NewNSXTMgr.AdminUser
$nsxMgrOvfConfig.Common.nsx_cli_passwd_0.Value = $config.NSXT_Deployment.NewNSXTMgr.AdminPassword
$nsxMgrOvfConfig.Common.nsx_cli_audit_username.Value = $config.NSXT_Deployment.NewNSXTMgr.Auditor
$nsxMgrOvfConfig.Common.nsx_cli_audit_passwd_0.Value = $config.NSXT_Deployment.NewNSXTMgr.AuditorPassword

My-Logger "Deploying NSX Manager VM $($config.NSXT_Deployment.NewNSXTMgr.hostname) ..."
$nsxmgr_vm = Import-VApp -Source $config.NSXT_Deployment.NewNSXTMgr.FilePath -OvfConfiguration $nsxMgrOvfConfig -Name $config.NSXT_Deployment.NewNSXTMgr.Name -Location $cluster -VMHost $vmhost -Datastore $datastore -DiskStorageFormat thin -Force

My-Logger "Updating vCPU Count to $($config.NSXT_Deployment.NewNSXTMgr.vCPU) & vMEM to $($config.NSXT_Deployment.NewNSXTMgr.vMEM) GB ..."
Set-VM -Server $viConnection -VM $nsxmgr_vm -NumCpu $config.NSXT_Deployment.NewNSXTMgr.vCPU -MemoryGB $config.NSXT_Deployment.NewNSXTMgr.vMEM -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

My-Logger "Powering On $NSXTMgrDisplayName ..."
$nsxmgr_vm | Start-Vm -RunAsync | Out-Null

### Then, NSX Controller
$nsxCtrOvfConfig = Get-OvfConfiguration $config.NSXT_Deployment.NewNSXTController.FilePath
$config.NSXT_Deployment.NewNSXTController.ControllerIPs.GetEnumerator() | Foreach-Object {
    $temp = $_.PSObject.properties
    $VMName = $temp.Name
    $VMIPAddress = $temp.Value
    $VMHostname = "$VMName" + "@" + $config.NSXT_Deployment.DeployTo.VMDomain

    $nsxCtrOvfConfig.NetworkMapping.Network_1.value = $config.NSXT_Deployment.DeployTo.VMNetwork
    $nsxCtrOvfConfig.Common.nsx_hostname.Value = $VMHostname
    $nsxCtrOvfConfig.Common.nsx_ip_0.Value = $VMIPAddress
    $nsxCtrOvfConfig.Common.nsx_netmask_0.Value = $config.NSXT_Deployment.DeployTo.Netmask
    $nsxCtrOvfConfig.Common.nsx_gateway_0.Value = $config.NSXT_Deployment.DeployTo.Gateway
    $nsxCtrOvfConfig.Common.nsx_dns1_0.Value = $config.NSXT_Deployment.DeployTo.DNS
    $nsxCtrOvfConfig.Common.nsx_domain_0.Value = $config.NSXT_Deployment.DeployTo.VMDomain
    $nsxCtrOvfConfig.Common.nsx_ntp_0.Value = $config.NSXT_Deployment.DeployTo.NTP

    if($config.NSXT_Deployment.NewNSXTController.SSHEnable -eq "True") {
        $NSXSSHEnableVar = $true
    } else {
        $NSXSSHEnableVar = $false
    }
    $nsxCtrOvfConfig.Common.nsx_isSSHEnabled.Value = $NSXSSHEnableVar
    if($config.NSXT_Deployment.NewNSXTController.SSHEnableRootLogin -eq "True") {
        $NSXRootPasswordVar = $true
    } else {
        $NSXRootPasswordVar = $false
    }
    $nsxCtrOvfConfig.Common.nsx_allowSSHRootLogin.Value = $NSXRootPasswordVar
    
    $nsxCtrOvfConfig.Common.nsx_passwd_0.Value = $config.NSXT_Deployment.NewNSXTController.Password
    $nsxCtrOvfConfig.Common.nsx_cli_username.Value = $config.NSXT_Deployment.NewNSXTController.AdminUser
    $nsxCtrOvfConfig.Common.nsx_cli_passwd_0.Value = $config.NSXT_Deployment.NewNSXTController.AdminPassword
    $nsxCtrOvfConfig.Common.nsx_cli_audit_username.Value = $config.NSXT_Deployment.NewNSXTController.Auditor
    $nsxCtrOvfConfig.Common.nsx_cli_audit_passwd_0.Value = $config.NSXT_Deployment.NewNSXTController.AuditorPassword

    My-Logger "Deploying NSX Controller VM $VMName ..."
    $nsxctr_vm = Import-VApp -Source $config.NSXT_Deployment.NewNSXTController.FilePath -OvfConfiguration $nsxCtrOvfConfig -Name $VMName -Location $cluster -VMHost $vmhost -Datastore $datastore -DiskStorageFormat thin -Force

    My-Logger "Updating vCPU Count to $($config.NSXT_Deployment.NewNSXTController.vCPU) & vMEM to $($config.NSXT_Deployment.NewNSXTController.vMEM) GB ..."
    Set-VM -Server $viConnection -VM $nsxctr_vm -NumCpu $config.NSXT_Deployment.NewNSXTController.vCPU -MemoryGB $config.NSXT_Deployment.NewNSXTController.vMEM -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

    My-Logger "Powering On $VMName ..."
    $nsxctr_vm | Start-Vm -RunAsync | Out-Null
}
### Then, NSX Edge
$nsxEdgeOvfConfig = Get-OvfConfiguration $config.NSXT_Deployment.NewNSXTEdge.FilePath
$config.NSXT_Deployment.NewNSXTEdge.EdgeIPs.GetEnumerator() | Foreach-Object {
    $temp = $_.PSObject.properties
    $VMName = $temp.Name
    $VMIPAddress = $temp.Value
    $VMHostname = "$VMName" + "@" + $config.NSXT_Deployment.DeployTo.VMDomain

    $nsxEdgeOvfConfig.DeploymentOption.Value = $config.NSXT_Deployment.NewNSXTEdge.size
    $nsxEdgeOvfConfig.NetworkMapping.Network_0.value = $config.NSXT_Deployment.DeployTo.VMNetwork
    $nsxEdgeOvfConfig.NetworkMapping.Network_1.value = $config.NSXT_Deployment.DeployTo.privateNetwork
    $nsxEdgeOvfConfig.NetworkMapping.Network_2.value = $config.NSXT_Deployment.DeployTo.privateNetwork
    $nsxEdgeOvfConfig.NetworkMapping.Network_3.value = $config.NSXT_Deployment.DeployTo.privateNetwork

    $nsxEdgeOvfConfig.Common.nsx_hostname.Value = $VMHostname
    $nsxEdgeOvfConfig.Common.nsx_ip_0.Value = $VMIPAddress
    $nsxEdgeOvfConfig.Common.nsx_netmask_0.Value = $config.NSXT_Deployment.DeployTo.NetMask
    $nsxEdgeOvfConfig.Common.nsx_gateway_0.Value = $config.NSXT_Deployment.DeployTo.Gateway
    $nsxEdgeOvfConfig.Common.nsx_dns1_0.Value = $config.NSXT_Deployment.DeployTo.DNS
    $nsxEdgeOvfConfig.Common.nsx_domain_0.Value = $config.NSXT_Deployment.DeployTo.VMDomain
    $nsxEdgeOvfConfig.Common.nsx_ntp_0.Value = $config.NSXT_Deployment.DeployTo.NTP

    if($config.NSXT_Deployment.NewNSXTEdge.SSHEnable -eq "true") {
        $NSXSSHEnableVar = $true
    } else {
        $NSXSSHEnableVar = $false
    }
    $nsxEdgeOvfConfig.Common.nsx_isSSHEnabled.Value = $NSXSSHEnableVar
    if($config.NSXT_Deployment.NewNSXTEdge.SSHEnableRootLogin -eq "true") {
        $NSXRootPasswordVar = $true
    } else {
        $NSXRootPasswordVar = $false
    }
    $nsxEdgeOvfConfig.Common.nsx_allowSSHRootLogin.Value = $NSXRootPasswordVar

    $nsxEdgeOvfConfig.Common.nsx_passwd_0.Value = $config.NSXT_Deployment.NewNSXTEdge.Password
    $nsxEdgeOvfConfig.Common.nsx_cli_username.Value = $config.NSXT_Deployment.NewNSXTEdge.AdminUser
    $nsxEdgeOvfConfig.Common.nsx_cli_passwd_0.Value = $config.NSXT_Deployment.NewNSXTEdge.AdminPassword
    $nsxEdgeOvfConfig.Common.nsx_cli_audit_username.Value = $config.NSXT_Deployment.NewNSXTEdge.Auditor
    $nsxEdgeOvfConfig.Common.nsx_cli_audit_passwd_0.Value = $config.NSXT_Deployment.NewNSXTEdge.AuditorPassword

    My-Logger "Deploying NSX Edge VM $VMName ..."
    $nsxedge_vm = Import-VApp -Source $config.NSXT_Deployment.NewNSXTEdge.FilePath -OvfConfiguration $nsxEdgeOvfConfig -Name $VMName -Location $cluster -VMHost $vmhost -Datastore $datastore -DiskStorageFormat thin -Force

    My-Logger "Updating vCPU Count to $($config.NSXT_Deployment.NewNSXTEdge.vCPU) & vMEM to $($config.NSXT_Deployment.NewNSXTEdge.vMEM) GB ..."
    Set-VM -Server $viConnection -VM $nsxedge_vm -NumCpu $config.NSXT_Deployment.NewNSXTEdge.vCPU -MemoryGB $config.NSXT_Deployment.NewNSXTEdge.vMEM -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

    My-Logger "Reconfiguring Network Adapter 2 to $($config.NSXT_Deployment.DeployTo.privateNetwork) ..."
    $nsxedge_vm | Get-NetworkAdapter -Name "Network adapter 2" | Set-NetworkAdapter -Portgroup $config.NSXT_Deployment.DeployTo.privateNetwork -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

    My-Logger "Reconfiguring Network Adapter 3 to $($config.NSXT_Deployment.DeployTo.VMNetwork) ..."
    $nsxedge_vm | Get-NetworkAdapter -Name "Network adapter 3" | Set-NetworkAdapter -Portgroup $config.NSXT_Deployment.DeployTo.VMNetwork -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

    My-Logger "Powering On $VMName ..."
    $nsxedge_vm | Start-Vm -RunAsync | Out-Null    
}
My-Logger "Disconnecting from management vCenter Server ..."
Disconnect-VIServer -Server $viConnection -Confirm:$false

### Config NSX-T ###
# Connect to vCenter and NSX-T Simultaneously
Connect-VIServer $config.ExistingVC.Hostname -User $config.ExistingVC.Username -Password $config.ExistingVC.Password -WarningAction SilentlyContinue | Out-Null
if(!(Connect-NsxtServer -Server $config.NSXT_Deployment.NewNSXTMgr.hostname -Username $config.NSXT_Deployment.NewNSXTMgr.AdminUser -Password $config.NSXT_Deployment.NewNSXTMgr.AdminPassword -WarningAction SilentlyContinue)) {
    Write-Host -ForegroundColor Red "Unable to connect to NSX Manager, please check the deployment"
    exit
} else {
    My-Logger "Successfully logged into NSX Manager $NSXTMgrHostname  ..."
}
# Retrieve NSX Manager Thumbprint which will be needed later
My-Logger "Retrieving NSX Manager Thumbprint ..."
$nsxMgrID = (Get-NsxtService -Name "com.vmware.nsx.cluster.nodes").list().results.id
$nsxMgrCertThumbprint = (Get-NsxtService -Name "com.vmware.nsx.cluster.nodes").get($nsxMgrID).manager_role.api_listen_addr.certificate_sha256_thumbprint

### Setup NSX Controllers
$firstNSXController = ""
$nsxControllerCertThumbprint  = ""
$debug = $true
# Retrieve VC Thumbprint
if(($isWindows) -or ($Env:OS -eq "Windows_NT")) {
    $DestinationCtrThumprintStore = "$ENV:TMP\controller-thumbprint"
    $DestinationVCThumbprintStore = "$ENV:TMP\vc-thumbprint"
} else {
    $DestinationCtrThumprintStore = "/tmp/controller-thumbprint"
    $DestinationVCThumbprintStore = "/tmp/vc-thumbprint"
}

$config.NSXT_Deployment.NewNSXTController.ControllerIPs.GetEnumerator() | Foreach-Object {
    $temp = $_.PSObject.properties
    $nsxCtrName = $temp.Name
    $nsxCtrIp = $temp.Value
    if($firstNSXController -eq "") {
        My-Logger "Configuring NSX Controller $nsxCtrName as control-cluster master ..."
        # Store the first NSX Controller for later use
        $firstNSXController = $nsxCtrName

        # Login by passing in admin username <enter>
        if($debug) { My-Logger "Sending admin username ..." }
        Set-VMKeystrokes -VMName $firstNSXController -StringInput $config.NSXT_Deployment.NewNSXTController.AdminUser -ReturnCarriage $true
        Start-Sleep 2

        # Login by passing in admin password <enter>
        if($debug) { My-Logger "Sending admin password ..." }
        Set-VMKeystrokes -VMName $firstNSXController -StringInput $config.NSXT_Deployment.NewNSXTController.AdminPassword -ReturnCarriage $true
        Start-Sleep 5

        # Join Controller to NSX Manager
        if($debug) { My-Logger "Sending join management plane command ..." }
        $joinMgmtCmd1 = "join management-plane $($config.NSXT_Deployment.NewNSXTMgr.IPAddress) username $($config.NSXT_Deployment.NewNSXTMgr.AdminUser) thumbprint $nsxMgrCertThumbprint"
        $joinMgmtCmd2 = "$($config.NSXT_Deployment.NewNSXTController.AdminPassword)"
        Set-VMKeystrokes -VMName $firstNSXController -StringInput $joinMgmtCmd1 -ReturnCarriage $true
        Start-Sleep 5
        Set-VMKeystrokes -VMName $firstNSXController -StringInput $joinMgmtCmd2 -ReturnCarriage $true
        Start-Sleep 25

        # Setup shared secret
        if($debug) { My-Logger "Sending shared secret command ..." }
        $sharedSecretCmd = "set control-cluster security-model shared-secret secret $($config.NSXT_Deployment.NewNSXTController.SharedSecret)"
        Set-VMKeystrokes -VMName $firstNSXController -StringInput $sharedSecretCmd -ReturnCarriage $true
        Start-Sleep  5

        # Initialize NSX Controller Cluster
        if($debug) { My-Logger "Sending control cluster init command ..." }
        $initCmd = "initialize control-cluster"
        Set-VMKeystrokes -VMName $firstNSXController -StringInput $initCmd -ReturnCarriage $true
        Start-Sleep 10
        # Exit from shell
        if($debug) { My-Logger "Sending exit command ..." }
        Set-VMKeystrokes -VMName $firstNSXController -StringInput "exit" -ReturnCarriage $true
        Start-Sleep 10
    } else {
        My-Logger "Configuring additional NSX Controller $nsxCtrName ..."

        if($debug) { My-Logger "Sending admin username ..." }
        Set-VMKeystrokes -VMName $nsxCtrName -StringInput $config.NSXT_Deployment.NewNSXTController.AdminUser -ReturnCarriage $true
        Start-Sleep 2        
        # Login by passing in admin password <enter>
        if($debug) { My-Logger "Sending admin password ..." }
        Set-VMKeystrokes -VMName $nsxCtrName -StringInput $config.NSXT_Deployment.NewNSXTController.AdminPassword -ReturnCarriage $true
        Start-Sleep 5

        # Join Controller to NSX Manager
        if($debug) { My-Logger "Sending join management plane command ..." }
        $joinMgmtCmd1 = "join management-plane $($config.NSXT_Deployment.NewNSXTMgr.IPAddress) username $($config.NSXT_Deployment.NewNSXTMgr.AdminUser) thumbprint $nsxMgrCertThumbprint"
        $joinMgmtCmd2 = "$($config.NSXT_Deployment.NewNSXTMgr.AdminPassword)"
        Set-VMKeystrokes -VMName $nsxCtrName -StringInput $joinMgmtCmd1 -ReturnCarriage $true
        Start-Sleep 5
        Set-VMKeystrokes -VMName $nsxCtrName -StringInput $joinMgmtCmd2 -ReturnCarriage $true
        Start-Sleep 25

        # Setup shared secret
        if($debug) { My-Logger "Sending shared secret command ..." }
        $sharedSecretCmd = "set control-cluster security-model shared-secret secret $($config.NSXT_Deployment.NewNSXTController.SharedSecret)"
        Set-VMKeystrokes -VMName $nsxCtrName -StringInput $sharedSecretCmd -ReturnCarriage $true
        Start-Sleep 5
        ### --- (stupid hack because we don't have an API) --- ###
        # Exit from nsxcli
        if($debug) { My-Logger "Sending exit command ..." }
        Set-VMKeystrokes -VMName $nsxCtrName -StringInput "exit" -ReturnCarriage $true
        Start-Sleep 10
        # Login using root
        if($debug) { My-Logger "Sending root username ..." }
        Set-VMKeystrokes -VMName $nsxCtrName -StringInput "root" -ReturnCarriage $true
        Start-Sleep 2

        # Login by passing in root password <enter>
        if($debug) { My-Logger "Sending root password ..." }
        Set-VMKeystrokes -VMName $nsxCtrName -StringInput $config.NSXT_Deployment.NewNSXTController.Password -ReturnCarriage $true
        
        # Retrieve Controller Thumbprint
        if($debug) { My-Logger "Sending get control cluster cert ..." }
        $ctrClusterThumbprintCmd = "nsxcli -c `"get control-cluster certificate thumbprint`" > /tmp/controller-thumbprint"
        Set-VMKeystrokes -VMName $nsxCtrName -StringInput $ctrClusterThumbprintCmd -ReturnCarriage $true
        Start-Sleep 25
        if($debug) { My-Logger "Sending get control cluster cert ..." }
        Copy-VMGuestFile -vm (Get-VM -Name $nsxCtrName) -GuestToLocal -GuestUser "root" -GuestPassword $config.NSXT_Deployment.NewNSXTController.Password -Source /tmp/controller-thumbprint -Destination $DestinationCtrThumprintStore | Out-Null
        $nsxControllerCertThumbprint = Get-Content -Path $DestinationCtrThumprintStore | ? {$_.trim() -ne "" }
        # Exit from shell
        if($debug) { My-Logger "Sending exit command ..." }
        Set-VMKeystrokes -VMName $nsxCtrName -StringInput "exit" -ReturnCarriage $true
        Start-Sleep 10

        # Join NSX Controller to NSX Controller Cluster
        # Login by passing in admin username <enter>
        if($debug) { My-Logger "Sending admin username ..." }
        Set-VMKeystrokes -VMName $firstNSXController -StringInput $config.NSXT_Deployment.NewNSXTController.AdminUser -ReturnCarriage $true
        Start-Sleep 2

        # Login by passing in admin password <enter>
        if($debug) { My-Logger "Sending admin password ..." }
        Set-VMKeystrokes -VMName $firstNSXController -StringInput $config.NSXT_Deployment.NewNSXTController.AdminPassword -ReturnCarriage $true
        Start-Sleep 5

        # Join NSX Controller to NSX Controller Cluster
        if($debug) { My-Logger "Sending join control cluster command ..." }
        $joinCtrCmd = "join control-cluster $nsxCtrIp thumbprint $nsxControllerCertThumbprint"
        Set-VMKeystrokes -VMName $firstNSXController -StringInput $joinCtrCmd -ReturnCarriage $true
        Start-Sleep 30
        # Exit from shell
        if($debug) { My-Logger "Sending exit command ..." }
        Set-VMKeystrokes -VMName $firstNSXController -StringInput "exit" -ReturnCarriage $true
        Start-Sleep 10

        # To activate control-cluster
        # Login by passing in admin username <enter>
        if($debug) { My-Logger "Sending admin username ..." }
        Set-VMKeystrokes -VMName $nsxCtrName -StringInput $config.NSXT_Deployment.NewNSXTController.AdminUser -ReturnCarriage $true
        Start-Sleep 2

        # Login by passing in admin password <enter>
        if($debug) { My-Logger "Sending admin password ..." }
        Set-VMKeystrokes -VMName $nsxCtrName -StringInput $config.NSXT_Deployment.NewNSXTController.AdminPassword -ReturnCarriage $true
        Start-Sleep 5
        # Activate NSX Controller
        if($debug) { My-Logger "Sending control cluster activate command ..." }
        $initCmd = "activate control-cluster"
        Set-VMKeystrokes -VMName $nsxCtrName -StringInput $initCmd -ReturnCarriage $true
        Start-Sleep 30

        # Exit Console
        if($debug) { My-Logger "Sending final exit ..." }
        Set-VMKeystrokes -VMName $nsxCtrName -StringInput "exit" -ReturnCarriage $true
    }
}
### Config NSX Edge
$config.NSXT_Deployment.NewNSXTEdge.EdgeIPs.GetEnumerator() | Foreach-Object {
    $temp = $_.PSObject.properties
    $nsxEdgeName = $temp.name
    $nsxEdgeIp = $temp.value

    My-Logger "Configuring NSX Edge $nsxEdgeName ..."

    # Login by passing in admin username <enter>
    if($debug) { My-Logger "Sending admin username ..." }
    Set-VMKeystrokes -VMName $nsxEdgeName -StringInput $config.NSXT_Deployment.NewNSXTEdge.AdminUser -ReturnCarriage $true
    Start-Sleep 2

    # Login by passing in admin password <enter>
    if($debug) { My-Logger "Sending admin password ..." }
    Set-VMKeystrokes -VMName $nsxEdgeName -StringInput $config.NSXT_Deployment.NewNSXTEdge.AdminPassword -ReturnCarriage $true
    Start-Sleep 5

    # Join NSX Edge to NSX Manager
    if($debug) { My-Logger "Sending join management plane command ..." }
    $joinMgmtCmd1 = "join management-plane $($config.NSXT_Deployment.NewNSXTMgr.hostname) username $($config.NSXT_Deployment.NewNSXTMgr.AdminUser) thumbprint $nsxMgrCertThumbprint"
    $joinMgmtCmd2 = "$($config.NSXT_Deployment.NewNSXTMgr.AdminPassword)"
    Set-VMKeystrokes -VMName $nsxEdgeName -StringInput $joinMgmtCmd1 -ReturnCarriage $true
    Start-Sleep 5
    Set-VMKeystrokes -VMName $nsxEdgeName -StringInput $joinMgmtCmd2 -ReturnCarriage $true
    Start-Sleep 20

    # Exit Console
    if($debug) { My-Logger "Sending final exit ..." }
    Set-VMKeystrokes -VMName $nsxEdgeName -StringInput "exit" -ReturnCarriage $true
}
My-Logger "Disconnecting from NSX Manager ..."
Disconnect-NsxtServer -Confirm:$false
    
My-Logger "Disconnecting from Management vCenter ..."
Disconnect-VIServer * -Confirm:$false

#### Deploy T0/T1 on NSX
if(!(Connect-NsxtServer -Server $config.NSXT_Deployment.NewNSXTMgr.hostname -Username $config.NSXT_Deployment.NewNSXTMgr.AdminUser -Password $config.NSXT_Deployment.NewNSXTMgr.AdminPassword -WarningAction SilentlyContinue)) {
    Write-Host -ForegroundColor Red "Unable to connect to NSX Manager, please check the deployment"
    exit
} else {
    My-Logger "Successfully logged into NSX Manager $($config.NSXT_Deployment.NewNSXTMgr.Name)  ..."
}
### Health Check for Controller nodes
My-Logger "Verifying health of all NSX Manager/Controller Nodes ..."
$clusterNodeService = Get-NsxtService -Name "com.vmware.nsx.cluster.nodes"
$clusterNodeStatusService = Get-NsxtService -Name "com.vmware.nsx.cluster.nodes.status"
$nodes = $clusterNodeService.list().results
$mgmtNodes = $nodes | Where-Object { $_.controller_role -eq $null }
$controllerNodes = $nodes | Where-Object { $_.manager_role -eq $null }

foreach ($mgmtNode in $mgmtNodes) {
    $mgmtNodeId = $mgmtNode.id
    $mgmtNodeName = $mgmtNode.appliance_mgmt_listen_addr

    if($debug) { My-Logger "Check health status of Mgmt Node $mgmtNodeName ..." }
    while ( $clusterNodeStatusService.get($mgmtNodeId).mgmt_cluster_status.mgmt_cluster_status -ne "CONNECTED") {
        if($debug) { My-Logger "$mgmtNodeName is not ready, sleeping 20 seconds ..." }
        Start-Sleep 20
    }
}

foreach ($controllerNode in $controllerNodes) {
    $controllerNodeId = $controllerNode.id
    $controllerNodeName = $controllerNode.controller_role.control_plane_listen_addr.ip_address

    if($debug) { My-Logger "Checking health of Ctrl Node $controllerNodeName ..." }
    while ( $clusterNodeStatusService.get($controllerNodeId).control_cluster_status.control_cluster_status -ne "CONNECTED") {
        if($debug) { My-Logger "$controllerNodeName is not ready, sleeping 20 seconds ..." }
        Start-Sleep 20
    }
}
### Acknowledge EULA
My-Logger "Accepting NSX Manager EULA ..."
$eulaService = Get-NsxtService -Name "com.vmware.nsx.eula.accept"
$eulaService.create()

### Create IPPools
## Tunnel Endpoint (TEP)
My-Logger "Creating Tunnel Endpoint IP Pool for ESXi ..."
$ipPoolService = Get-NsxtService -Name "com.vmware.nsx.pools.ip_pools"
$ipPoolSpec = $ipPoolService.help.create.ip_pool.Create()
$subNetSpec = $ipPoolService.help.create.ip_pool.subnets.Element.Create()
$allocationRangeSpec = $ipPoolService.help.create.ip_pool.subnets.Element.allocation_ranges.Element.Create()

$allocationRangeSpec.start = $config.NSXT_Deployment.NewNSXTMgr.TunnelEndPointPool.IPRangeStart
$allocationRangeSpec.end = $config.NSXT_Deployment.NewNSXTMgr.TunnelEndPointPool.IPRangeEnd
$addResult = $subNetSpec.allocation_ranges.Add($allocationRangeSpec)
$subNetSpec.cidr = $config.NSXT_Deployment.NewNSXTMgr.TunnelEndPointPool.CIDR
$subNetSpec.gateway_ip = $config.NSXT_Deployment.NewNSXTMgr.TunnelEndPointPool.Gateway
$ipPoolSpec.display_name = $config.NSXT_Deployment.NewNSXTMgr.TunnelEndPointPool.Name
$ipPoolSpec.description = $config.NSXT_Deployment.NewNSXTMgr.TunnelEndPointPool.Description
$addResult = $ipPoolSpec.subnets.Add($subNetSpec)
$ipPool = $ipPoolService.create($ipPoolSpec)
## LoadBalancer Pool
My-Logger "Creating Load Balancer IP Pool for K8S ..."
$ipPoolService = Get-NsxtService -Name "com.vmware.nsx.pools.ip_pools"
$ipPoolSpec = $ipPoolService.help.create.ip_pool.Create()
$subNetSpec = $ipPoolService.help.create.ip_pool.subnets.Element.Create()
$allocationRangeSpec = $ipPoolService.help.create.ip_pool.subnets.Element.allocation_ranges.Element.Create()

$allocationRangeSpec.start = $config.NSXT_Deployment.NewNSXTMgr.LoadBalancerPool.IPRangeStart
$allocationRangeSpec.end = $config.NSXT_Deployment.NewNSXTMgr.LoadBalancerPool.IPRangeEnd
$addResult = $subNetSpec.allocation_ranges.Add($allocationRangeSpec)
$subNetSpec.cidr = $config.NSXT_Deployment.NewNSXTMgr.LoadBalancerPool.CIDR
$ipPoolSpec.display_name = $config.NSXT_Deployment.NewNSXTMgr.LoadBalancerPool.Name
$ipPoolSpec.description = $config.NSXT_Deployment.NewNSXTMgr.LoadBalancerPool.Description
$addResult = $ipPoolSpec.subnets.Add($subNetSpec)
$ipPool = $ipPoolService.create($ipPoolSpec)

## K8S IP Block
My-Logger "Creating PKS IP Block ..."
$ipBlockService = Get-NsxtService -Name "com.vmware.nsx.pools.ip_blocks"
$ipBlockSpec = $ipBlockService.Help.create.ip_block.Create()
$ipBlockSpec.display_name = $config.NSXT_Deployment.NewNSXTMgr.IPBlock.Name
$ipBlockSpec.cidr = $config.NSXT_Deployment.NewNSXTMgr.IPBlock.Network
$ipBlockAdd = $ipBlockService.create($ipBlockSpec)

### Create Transport Zone
My-Logger "Creating Overlay & VLAN Transport Zones ..."
$transportZoneService = Get-NsxtService -Name "com.vmware.nsx.transport_zones"
$overlayTZSpec = $transportZoneService.help.create.transport_zone.Create()
$overlayTZSpec.display_name = $config.NSXT_Deployment.NewNSXTMgr.TransportZone.OverlayTZName
$overlayTZSpec.host_switch_name = $config.NSXT_Deployment.NewNSXTMgr.TransportZone.OverlayTZSwitch
$overlayTZSpec.transport_type = "OVERLAY"
$overlayTZ = $transportZoneService.create($overlayTZSpec)

$vlanTZSpec = $transportZoneService.help.create.transport_zone.Create()
$vlanTZSpec.display_name = $config.NSXT_Deployment.NewNSXTMgr.TransportZone.vLANTZName
$vlanTZSpec.host_switch_name = $config.NSXT_Deployment.NewNSXTMgr.TransportZone.vLANTZSwitch
$vlanTZSpec.transport_type = "VLAN"
$vlanTZ = $transportZoneService.create($vlanTZSpec)

### Add NewVC
## Retrieve VC Thumbprint
if($debug) { My-Logger "Sending openssl to get VC Thumbprint ..." }
if($debug) { My-Logger "Sending root username ..." }
Set-VMKeystrokes -VMName $config.NSXT_Deployment.NewNSXTMgr.Name -StringInput "root" -ReturnCarriage $true
Start-Sleep 10
# Login by passing in root password <enter>
if($debug) { My-Logger "Sending root password ..." }
Set-VMKeystrokes -VMName $config.NSXT_Deployment.NewNSXTMgr.Name -StringInput $config.NSXT_Deployment.NewNSXTMgr.RootPassword -ReturnCarriage $true
Start-Sleep 10
$vcThumbprintCmd = "echo -n | openssl s_client -connect $($config.vSphere_Deployment.NewVCSA.HostName):443 2>/dev/null | openssl x509 -noout -fingerprint -sha256 | awk -F `'=`' `'{print `$2}`' > /tmp/vc-thumbprint"
Set-VMKeystrokes -VMName $config.NSXT_Deployment.NewNSXTMgr.Name -StringInput $vcThumbprintCmd -ReturnCarriage $true
Start-Sleep 30
if($debug) { My-Logger "Processing certificate thumbprint ..." }
Copy-VMGuestFile -vm (Get-VM -Name $config.NSXT_Deployment.NewNSXTMgr.Name) -GuestToLocal -GuestUser "root" -GuestPassword $config.NSXT_Deployment.NewNSXTController.Password -Source /tmp/vc-thumbprint -Destination $DestinationVCThumbprintStore | Out-Null
$vcCertThumbprint = Get-Content -Path $DestinationVCThumbprintStore
Set-VMKeystrokes -VMName $config.NSXT_Deployment.NewNSXTMgr.Name -StringInput "exit" -ReturnCarriage $true

## Add VC
My-Logger "Adding vCenter Server Compute Manager ..."
$computeManagerService = Get-NsxtService -Name "com.vmware.nsx.fabric.compute_managers"
$computeManagerStatusService = Get-NsxtService -Name "com.vmware.nsx.fabric.compute_managers.status"

$computeManagerSpec = $computeManagerService.help.create.compute_manager.Create()
$credentialSpec = $computeManagerService.help.create.compute_manager.credential.username_password_login_credential.Create()
$credentialSpec.username = "administrator@$($config.vSphere_Deployment.NewVCSA.SSODomain)"
$credentialSpec.password = $config.vSphere_Deployment.NewVCSA.SSOPassword
$credentialSpec.thumbprint = $vcCertThumbprint
$computeManagerSpec.server = $config.vSphere_Deployment.NewVCSA.HostName
$computeManagerSpec.origin_type = "vCenter"
$computeManagerSpec.display_name = $config.vSphere_Deployment.NewVCSA.Name
$computeManagerSpec.credential = $credentialSpec
$computeManagerResult = $computeManagerService.create($computeManagerSpec)

if($debug) { My-Logger "Waiting for VC registration to complete ..." }
    while ( $computeManagerStatusService.get($computeManagerResult.id).registration_status -ne "REGISTERED") {
        if($debug) { My-Logger "$VIServer is not ready, sleeping 30 seconds ..." }
        Start-Sleep 30
}
## Run Host Preparation
My-Logger "Preparing ESXi hosts & Installing NSX VIBs ..."
$computeCollectionService = Get-NsxtService -Name "com.vmware.nsx.fabric.compute_collections"
$computeId = $computeCollectionService.list().results[0].external_id

$computeCollectionFabricTemplateService = Get-NsxtService -Name "com.vmware.nsx.fabric.compute_collection_fabric_templates"
$computeFabricTemplateSpec = $computeCollectionFabricTemplateService.help.create.compute_collection_fabric_template.Create()
$computeFabricTemplateSpec.auto_install_nsx = $true
$computeFabricTemplateSpec.compute_collection_id = $computeId
$computeCollectionFabric = $computeCollectionFabricTemplateService.create($computeFabricTemplateSpec)

My-Logger "Waiting for ESXi hosts to finish host prep ..."
$fabricNodes = (Get-NsxtService -Name "com.vmware.nsx.fabric.nodes").list().results | where { $_.resource_type -eq "HostNode" }
foreach ($fabricNode in $fabricNodes) {
    $fabricNodeName = $fabricNode.display_name
    while ((Get-NsxtService -Name "com.vmware.nsx.fabric.nodes.status").get($fabricNode.external_id).host_node_deployment_status -ne "INSTALL_SUCCESSFUL") {
        if($debug) { My-Logger "ESXi hosts are still being prepped, sleeping for 30 seconds ..." }
        Start-Sleep 30
    }
}

### Create Uplink Profile for Edge
$hostSwitchProfileService = Get-NsxtService -Name "com.vmware.nsx.host_switch_profiles"
My-Logger "Creating ESXi Uplink Profile ..."
$ESXiUplinkProfileSpec = $hostSwitchProfileService.help.create.base_host_switch_profile.uplink_host_switch_profile.Create()
$activeUplinkSpec = $hostSwitchProfileService.help.create.base_host_switch_profile.uplink_host_switch_profile.teaming.active_list.Element.Create()
$activeUplinkSpec.uplink_name = $config.NSXT_Deployment.NewNSXTMgr.UplinkProfile.ESXi.ActivepNIC
$activeUplinkSpec.uplink_type = "PNIC"
$ESXiUplinkProfileSpec.display_name = $config.NSXT_Deployment.NewNSXTMgr.UplinkProfile.ESXi.Name
$ESXiUplinkProfileSpec.mtu = $config.NSXT_Deployment.NewNSXTMgr.UplinkProfile.ESXi.MTU
$ESXiUplinkProfileSpec.transport_vlan = $config.NSXT_Deployment.NewNSXTMgr.UplinkProfile.ESXi.TransportVLAN
$addActiveUplink = $ESXiUplinkProfileSpec.teaming.active_list.Add($activeUplinkSpec)
$ESXiUplinkProfileSpec.teaming.policy = $config.NSXT_Deployment.NewNSXTMgr.UplinkProfile.ESXi.ProfilePolicy
$ESXiUplinkProfile = $hostSwitchProfileService.create($ESXiUplinkProfileSpec)

My-Logger "Creating Edge Uplink Profile ..."
$EdgeUplinkProfileSpec = $hostSwitchProfileService.help.create.base_host_switch_profile.uplink_host_switch_profile.Create()
$activeUplinkSpec = $hostSwitchProfileService.help.create.base_host_switch_profile.uplink_host_switch_profile.teaming.active_list.Element.Create()
$activeUplinkSpec.uplink_name = $config.NSXT_Deployment.NewNSXTMgr.UplinkProfile.Edge.ActivepNIC
$activeUplinkSpec.uplink_type = "PNIC"
$EdgeUplinkProfileSpec.display_name = $config.NSXT_Deployment.NewNSXTMgr.UplinkProfile.Edge.Name
$EdgeUplinkProfileSpec.mtu = $config.NSXT_Deployment.NewNSXTMgr.UplinkProfile.Edge.MTU
$EdgeUplinkProfileSpec.transport_vlan = $config.NSXT_Deployment.NewNSXTMgr.UplinkProfile.Edge.TransportVLAN
$addActiveUplink = $EdgeUplinkProfileSpec.teaming.active_list.Add($activeUplinkSpec)
$EdgeUplinkProfileSpec.teaming.policy = $config.NSXT_Deployment.NewNSXTMgr.UplinkProfile.Edge.ProfilePolicy
$EdgeUplinkProfile = $hostSwitchProfileService.create($EdgeUplinkProfileSpec)

### Add Logical Switch
My-Logger "Adding Logical Switch for K8S Management Cluster ..."
$logicalSwitchService = Get-NsxtService -Name "com.vmware.nsx.logical_switches"
$logicalSwitchSpec = $logicalSwitchService.help.create.logical_switch.Create()
$logicalSwitchSpec.display_name = $config.NSXT_Deployment.NewNSXTMgr.LogicalSwitch.K8sMgmt.Name
$logicalSwitchSpec.admin_state = "UP"
$logicalSwitchSpec.replication_mode = $config.NSXT_Deployment.NewNSXTMgr.LogicalSwitch.K8sMgmt.ReplicationMode
$logicalSwitchSpec.transport_zone_id = $overlayTZ.id
$uplinkLogicalSwitch = $logicalSwitchService.create($logicalSwitchSpec)

My-Logger "Adding Logical Switch for Uplink ..."
$logicalSwitchService = Get-NsxtService -Name "com.vmware.nsx.logical_switches"
$logicalSwitchSpec = $logicalSwitchService.help.create.logical_switch.Create()
$logicalSwitchSpec.display_name = $config.NSXT_Deployment.NewNSXTMgr.LogicalSwitch.Uplink.Name
$logicalSwitchSpec.admin_state = "UP"
$logicalSwitchSpec.vlan = $config.NSXT_Deployment.NewNSXTMgr.LogicalSwitch.Uplink.VLAN
$logicalSwitchSpec.transport_zone_id = $vlanTZ.id
$uplinkLogicalSwitch = $logicalSwitchService.create($logicalSwitchSpec)

### Add Transport-Node for Edge
My-Logger "Add Transport-Node for Edge..."
$transportNodeService = Get-NsxtService -Name "com.vmware.nsx.transport_nodes"
$transportNodeStateService = Get-NsxtService -Name "com.vmware.nsx.transport_nodes.state"

# Retrieve all Edge Host Nodes
$edgeNodes = (Get-NsxtService -Name "com.vmware.nsx.fabric.nodes").list().results | where { $_.resource_type -eq "EdgeNode" }
$EdgeUplinkProfile = (Get-NsxtService -Name "com.vmware.nsx.host_switch_profiles").list().results | where { $_.display_name -eq $config.NSXT_Deployment.NewNSXTMgr.UplinkProfile.Edge.Name}
$ipPool = (Get-NsxtService -Name "com.vmware.nsx.pools.ip_pools").list().results | where { $_.display_name -eq $config.NSXT_Deployment.NewNSXTMgr.TunnelEndPointPool.Name }
$overlayTransportZone = (Get-NsxtService -Name "com.vmware.nsx.transport_zones").list().results | where { $_.transport_type -eq "OVERLAY" }
$vlanTransportZone = (Get-NsxtService -Name "com.vmware.nsx.transport_zones").list().results | where { $_.transport_type -eq "VLAN" }

foreach ($edgeNode in $edgeNodes) {
    $edgeNodeName = $edgeNode.display_name
    My-Logger "Adding $edgeNodeName Edge Transport Node ..."

    # Create all required empty specs
    $transportNodeSpec = $transportNodeService.help.create.transport_node.Create()
    $hostSwitchOverlaySpec = $transportNodeService.help.create.transport_node.host_switches.Element.Create()
    $hostSwitchVlanSpec = $transportNodeService.help.create.transport_node.host_switches.Element.Create()
    $hostSwitchProfileSpec = $transportNodeService.help.create.transport_node.host_switches.Element.host_switch_profile_ids.Element.Create()
    $pnicOverlaySpec = $transportNodeService.help.create.transport_node.host_switches.Element.pnics.Element.Create()
    $pnicVlanSpec = $transportNodeService.help.create.transport_node.host_switches.Element.pnics.Element.Create()
    $transportZoneEPOverlaySpec = $transportNodeService.help.create.transport_node.transport_zone_endpoints.Element.Create()
    $transportZoneEPVlanSpec = $transportNodeService.help.create.transport_node.transport_zone_endpoints.Element.Create()

    $transportNodeSpec.display_name = $edgeNodeName

    $hostSwitchOverlaySpec.host_switch_name = $OverlayTransportZoneHostSwitchName
    $hostSwitchProfileSpec.key = "UplinkHostSwitchProfile"
    $hostSwitchProfileSpec.value = $EdgeUplinkProfile.id
    $pnicOverlaySpec.device_name = $EdgeUplinkProfileOverlayvNIC
    $pnicOverlaySpec.uplink_name = $EdgeUplinkProfileActivepNIC
    $hostSwitchOverlaySpec.static_ip_pool_id = $ipPool.id
    $pnicAddResult = $hostSwitchOverlaySpec.pnics.Add($pnicOverlaySpec)
    $switchProfileAddResult = $hostSwitchOverlaySpec.host_switch_profile_ids.Add($hostSwitchProfileSpec)
    $switchAddResult = $transportNodeSpec.host_switches.Add($hostSwitchOverlaySpec)

    $hostSwitchVlanSpec.host_switch_name = $VlanTransportZoneNameHostSwitchName
    $hostSwitchProfileSpec.key = "UplinkHostSwitchProfile"
    $hostSwitchProfileSpec.value = $EdgeUplinkProfile.id
    $pnicVlanSpec.device_name = $EdgeUplinkProfileVlanvNIC
    $pnicVlanSpec.uplink_name = $EdgeUplinkProfileActivepNIC
    $pnicAddResult = $hostSwitchVlanSpec.pnics.Add($pnicVlanSpec)
    $switchProfileAddResult = $hostSwitchVlanSpec.host_switch_profile_ids.Add($hostSwitchProfileSpec)
    $switchAddResult = $transportNodeSpec.host_switches.Add($hostSwitchVlanSpec)

    $transportZoneEPOverlaySpec.transport_zone_id = $overlayTransportZone.id
    $transportZoneAddResult = $transportNodeSpec.transport_zone_endpoints.Add($transportZoneEPOverlaySpec)

    $transportZoneEPVlanSpec.transport_zone_id = $vlanTransportZone.id
    $transportZoneAddResult = $transportNodeSpec.transport_zone_endpoints.Add($transportZoneEPVlanSpec)

    $transportNodeSpec.node_id = $edgeNode.id
    $transportNode = $transportNodeService.create($transportNodeSpec)

    My-Logger "Waiting for transport node configurations to complete ..."
    while ($transportNodeStateService.get($transportNode.id).state -ne "success") {
        if($debug) { My-Logger "ESXi transport node still being configured, sleeping for 30 seconds ..." }
        Start-Sleep 30
    }
}
### Add Transport Nodes
### Cannot figure NIOC Yet. The following code does not work. [TODO]
#$transportNodeService = Get-NsxtService -Name "com.vmware.nsx.transport_nodes"
#$transportNodeStateService = Get-NsxtService -Name "com.vmware.nsx.transport_nodes.state"
## Retrieve all ESXi Host Nodes
#$hostNodes = (Get-NsxtService -Name "com.vmware.nsx.fabric.nodes").list().results | where { $_.resource_type -eq "HostNode" }
#$ESXiUplinkProfile = (Get-NsxtService -Name "com.vmware.nsx.host_switch_profiles").list().results | where { $_.display_name -eq $config.NSXT_Deployment.NewNSXTMgr.UplinkProfile.ESXi.Name}
#$ipPool = (Get-NsxtService -Name "com.vmware.nsx.pools.ip_pools").list().results | where { $_.display_name -eq $config.NSXT_Deployment.NewNSXTMgr.TunnelEndPointPool.Name }
#$overlayTransportZone = (Get-NsxtService -Name "com.vmware.nsx.transport_zones").list().results | where { $_.transport_type -eq "OVERLAY" }
#$esxi_count = 1
#foreach ($hostNode in $hostNodes) {
#    $hostNodeName = "esxi-$($esxi_count)-TN"
#    My-Logger "Adding $hostNodeName Transport Node ..."

#    # Create all required empty specs
#    $transportNodeSpec = $transportNodeService.help.create.transport_node.Create()
#    $hostSwitchSpec = $transportNodeService.help.create.transport_node.host_switches.Element.Create()
#    $hostSwitchProfileSpec = $transportNodeService.help.create.transport_node.host_switches.Element.host_switch_profile_ids.Element.Create()
#    $pnicSpec = $transportNodeService.help.create.transport_node.host_switches.Element.pnics.Element.Create()
#    $transportZoneEPSpec = $transportNodeService.help.create.transport_node.transport_zone_endpoints.Element.Create()

#    $transportNodeSpec.display_name = $hostNodeName
#    $hostSwitchSpec.host_switch_name = $config.NSXT_Deployment.NewNSXTMgr.TransportZone.OverlayTZName
#    $hostSwitchProfileSpec.key = "UplinkHostSwitchProfile"
#    $hostSwitchProfileSpec.value = $ESXiUplinkProfile.id
#    $pnicSpec.device_name = $config.NSXT_Deployment.NewNSXTMgr.UplinkProfile.ESXi.ActivepNIC
#    $pnicSpec.uplink_name = $config.NSXT_Deployment.NewNSXTMgr.UplinkProfile.ESXi.ActivepNIC
#    $hostSwitchSpec.static_ip_pool_id = $ipPool.id
#    $pnicAddResult = $hostSwitchSpec.pnics.Add($pnicSpec)
#    $switchProfileAddResult = $hostSwitchSpec.host_switch_profile_ids.Add($hostSwitchProfileSpec)
#    $switchAddResult = $transportNodeSpec.host_switches.Add($hostSwitchSpec)
#    $transportZoneEPSpec.transport_zone_id = $overlayTransportZone.id
#    $transportZoneAddResult = $transportNodeSpec.transport_zone_endpoints.Add($transportZoneEPSpec)
#    $transportNodeSpec.node_id = $hostNode.id
#    $transportNode = $transportNodeService.create($transportNodeSpec)

#    My-Logger "Waiting for transport node configurations to complete ..."
#    while ($transportNodeStateService.get($transportNode.id).state -ne "success") {
#        if($debug) { My-Logger "ESXi transport node still being configured, sleeping for 30 seconds ..." }
#        Start-Sleep 30
#    }
#    $esxi_count++
#}

