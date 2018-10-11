### This file is to deploy Nested Hypervisor ###
Import-Module -Name ./functions.psm1 -Verbose
$config = Get-Content ./Nested-Parameters.json | Out-String | ConvertFrom-Json
$verboseLogFile = "./shawn-debug.log"
### Test Variables ###
if(!(Test-Path $config.vSphere_Deployment.NestedESXiResources.FilePath)) {
    Write-Host -ForegroundColor Red "`nUnable to find $($config.vSphere_Deployment.NestedESXiResources.FilePath) ...`nexiting"
    exit
}
if (!(Test-Path $config.vSphere_Deployment.NewVCSA.FilePath)){
    Write-Host -ForegroundColor Red "Unable to find $($config.vSphere_Deployment.NewVCSA.FilePath)"
}
My-Logger "Retrieve Parameters from viConnection"
$viConnection = Connect-VIServer -Server $config.ExistingVC.IPAddress -User $config.ExistingVC.Username -Password $config.ExistingVC.Password -WarningAction SilentlyContinue
$network = Get-VDPortgroup -Server $viConnection -Name $config.vSphere_Deployment.DeployTo.VMNetwork | Select -First 1
$cluster = Get-Cluster -Server $viConnection -Name $config.vSphere_Deployment.DeployTo.Cluster | Select -First 1
$datacenter = $cluster | Get-Datacenter
$vmhost = $cluster | Get-VMHost | Select -First 1
$datastore = Get-Datastore -Server $viConnection -Name $config.vSphere_Deployment.DeployTo.Datastore | Select -First 1
if($datastore.Type -eq "vsan") {
    My-Logger "VSAN Datastore detected, enabling Fake SCSI Reservations ..."
    Get-AdvancedSetting -Entity $vmhost -Name "VSAN.FakeSCSIReservations" | Set-AdvancedSetting -Value 1 -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
}
#$config.vSphere_Deployment.NestedESXiResources.NestedIPs.GetEnumerator() | Foreach-Object {
#    $temp = $_.PSObject.properties
#    $VMName = $temp.Name
#    $VMIPAddress = $temp.Value
#    Write-Host "VM:$VMName, Address:$VMIPAddress"
#}
$config.vSphere_Deployment.NestedESXiResources.NestedIPs.GetEnumerator() | Foreach-Object {
    $temp = $_.PSObject.properties
    $VMName = $temp.Name
    $VMIPAddress = $temp.Value

    $ovfconfig = Get-OvfConfiguration $config.vSphere_Deployment.NestedESXiResources.FilePath
    $ovfconfig.NetworkMapping.VM_Network_DVPG.value = $config.vSphere_Deployment.DeployTo.VMNetwork
    $ovfconfig.common.guestinfo.hostname.value = $VMName
    $ovfconfig.common.guestinfo.ipaddress.value = $VMIPAddress
    $ovfconfig.common.guestinfo.netmask.value = $config.vSphere_Deployment.DeployTo.NetMask
    $ovfconfig.common.guestinfo.gateway.value = $config.vSphere_Deployment.DeployTo.Gateway
    $ovfconfig.common.guestinfo.dns.value = $config.vSphere_Deployment.DeployTo.DNS
    $ovfconfig.common.guestinfo.domain.value = $config.vSphere_Deployment.NewVCSA.SSODomain
    $ovfconfig.common.guestinfo.ntp.value = $config.vSphere_Deployment.DeployTo.NTP
    $ovfconfig.common.guestinfo.syslog.value = $config.vSphere_Deployment.DeployTo.VMSyslog
    $ovfconfig.common.guestinfo.password.value = $config.vSphere_Deployment.NestedESXiResources.Password
    if($config.vSphere_Deployment.NestedESXiResources.SSHEnable -eq "true") {
        $VMSSHVar = $true
    } else {
        $VMSSHVar = $false
    }
    $ovfconfig.common.guestinfo.ssh.value = $VMSSHVar

    My-Logger "Deploying Nested ESXi VM $VMName ..."
    $vm = Import-VApp -Source $config.vSphere_Deployment.NestedESXiResources.FilePath -OvfConfiguration $ovfconfig -Name $VMName -Location $cluster -VMHost $vmhost -Datastore $datastore -DiskStorageFormat thin

    My-Logger "Adding vmnic2/vmnic3 to $NSXPrivatePortgroup ..."
    New-NetworkAdapter -VM $vm -Type Vmxnet3 -Portgroup $config.vSphere_Deployment.DeployTo.privateNetwork -StartConnected -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
    New-NetworkAdapter -VM $vm -Type Vmxnet3 -Portgroup $config.vSphere_Deployment.DeployTo.privateNetwork -StartConnected -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

    My-Logger "Updating vCPU Count to $($config.vSphere_Deployment.NestedESXiResources.vCPU) & vMEM to $($config.vSphere_Deployment.NestedESXiResources.vMem) GB ..."
    Set-VM -Server $viConnection -VM $vm -NumCpu $config.vSphere_Deployment.NestedESXiResources.vCPU -MemoryGB $config.vSphere_Deployment.NestedESXiResources.vMem -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

    My-Logger "Updating vSAN Caching VMDK size to $($config.vSphere_Deployment.NestedESXiResources.CachingDisk) GB ..."
    Get-HardDisk -Server $viConnection -VM $vm -Name "Hard disk 2" | Set-HardDisk -CapacityGB $config.vSphere_Deployment.NestedESXiResources.CachingDisk -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

    My-Logger "Updating vSAN Capacity VMDK size to $($config.vSphere_Deployment.NestedESXiResources.CapacityDisk) GB ..."
    Get-HardDisk -Server $viConnection -VM $vm -Name "Hard disk 3" | Set-HardDisk -CapacityGB $config.vSphere_Deployment.NestedESXiResources.CapacityDisk -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

    My-Logger "Powering On $vmname ..."
    $vm | Start-Vm -RunAsync | Out-Null
}
###
$cluster = Get-Cluster -Server $viConnection -Name $config.vSphere_Deployment.DeployTo.Cluster | Select -First 1
$datacenter = $cluster | Get-Datacenter
$vmhost = $cluster | Get-VMHost | Select -First 1
$datastore = Get-Datastore -Server $viConnection -Name $config.vSphere_Deployment.DeployTo.Datastore | Select -First 1
### Deploy vCenter ###
$config_vcsa = (Get-Content -Raw "$($config.vSphere_Deployment.NewVCSA.FilePath)\vcsa-cli-installer\templates\install\embedded_vCSA_on_VC.json") | convertfrom-json
$config_vcsa.'new.vcsa'.vc.hostname = $config.ExistingVC.Hostname
$config_vcsa.'new.vcsa'.vc.username = $config.ExistingVC.Username
$config_vcsa.'new.vcsa'.vc.password = $config.ExistingVC.Password
$config_vcsa.'new.vcsa'.vc.'deployment.network' = $config.vSphere_Deployment.DeployTo.VMNetwork
$config_vcsa.'new.vcsa'.vc.datastore = $datastore
$config_vcsa.'new.vcsa'.vc.datacenter = $datacenter.name
$config_vcsa.'new.vcsa'.vc.target = $config.vSphere_Deployment.DeployTo.Cluster
$config_vcsa.'new.vcsa'.appliance.'thin.disk.mode' = $true
$config_vcsa.'new.vcsa'.appliance.'deployment.option' = $config.vSphere_Deployment.NewVCSA.Size
$config_vcsa.'new.vcsa'.appliance.name = $config.vSphere_Deployment.NewVCSA.Name
$config_vcsa.'new.vcsa'.network.'ip.family' = "ipv4"
$config_vcsa.'new.vcsa'.network.mode = "static"
$config_vcsa.'new.vcsa'.network.ip = $config.vSphere_Deployment.NewVCSA.IPAddress
$config_vcsa.'new.vcsa'.network.'dns.servers'[0] = $config.vSphere_Deployment.DeployTo.DNS
$config_vcsa.'new.vcsa'.network.prefix = $config.vSphere_Deployment.NewVCSA.Prefix
$config_vcsa.'new.vcsa'.network.gateway = $config.vSphere_Deployment.DeployTo.Gateway
$config_vcsa.'new.vcsa'.network.'system.name' = $config.vSphere_Deployment.NewVCSA.HostName
$config_vcsa.'new.vcsa'.os.password = $config.vSphere_Deployment.NewVCSA.RootPassword
if($config.vSphere_Deployment.NewVCSA.SSHEnable -eq "true") {
    $VCSASSHEnableVar = $true
} else {
    $VCSASSHEnableVar = $false
}
$config_vcsa.'new.vcsa'.os.'ssh.enable' = $VCSASSHEnableVar
$config_vcsa.'new.vcsa'.sso.password = $config.vSphere_Deployment.NewVCSA.SSOPassword
$config_vcsa.'new.vcsa'.sso.'domain-name' = $config.vSphere_Deployment.NewVCSA.SSODomain
$config_vcsa.'new.vcsa'.sso.'site-name' = $config.vSphere_Deployment.NewVCSA.SiteName

My-Logger "Creating VCSA JSON Configuration file for deployment ..."
$config_vcsa | ConvertTo-Json | Set-Content -Path "$($ENV:Temp)\jsontemplate.json"

My-Logger "Deploying the VCSA ..."
Invoke-Expression "$($config.vSphere_Deployment.NewVCSA.FilePath)\vcsa-cli-installer\win32\vcsa-deploy.exe install --no-esx-ssl-verify --accept-eula --acknowledge-ceip $($ENV:Temp)\jsontemplate.json"| Out-File -Append -LiteralPath $verboseLogFile

My-Logger "Disconnecting from vCenter $($config.ExistingVC.Hostname) ..."
Disconnect-VIServer $viConnection -Confirm:$false

#### Setup new VC ####
My-Logger "Connecting to the new VCSA ..."
$vc = Connect-VIServer $config.vSphere_Deployment.NewVCSA.IPAddress -User "administrator@$($config.vSphere_Deployment.NewVCSA.SSODomain)" -Password $config.vSphere_Deployment.NewVCSA.SSOPassword -WarningAction SilentlyContinue

My-Logger "Creating Datacenter $($config.vSphere_Deployment.NewVCSA.DataCenter) ..."
New-Datacenter -Server $vc -Name $config.vSphere_Deployment.NewVCSA.DataCenter -Location (Get-Folder -Type Datacenter -Server $vc) | Out-File -Append -LiteralPath $verboseLogFile

My-Logger "Creating new VSAN Cluster $($config.vSphere_Deployment.NewVCSA.Cluster) ..."
New-Cluster -Server $vc -Name $config.vSphere_Deployment.NewVCSA.Cluster -Location $config.vSphere_Deployment.NewVCSA.DataCenter -DrsEnabled -VsanEnabled -VsanDiskClaimMode 'Manual' | Out-File -Append -LiteralPath $verboseLogFile


$config.vSphere_Deployment.NestedESXiResources.NestedIPs.GetEnumerator() | Foreach-Object {
    $temp = $_.PSObject.properties
    $VMName = $temp.Name
    $VMIPAddress = $temp.Value

    $targetVMHost = $VMIPAddress
    if($addHostByDnsName -eq 1) {
        $targetVMHost = $VMName
    }
    My-Logger "Adding ESXi host $targetVMHost to Cluster ..."
    Add-VMHost -Server $vc -Location (Get-Cluster -Name $config.vSphere_Deployment.NewVCSA.Cluster) -User "root" -Password $config.vSphere_Deployment.NestedESXiResources.Password -Name $targetVMHost -Force | Out-File -Append -LiteralPath $verboseLogFile
}

My-Logger "Enabling VSAN & disabling VSAN Health Check ..."
Get-VsanClusterConfiguration -Server $vc -Cluster $config.vSphere_Deployment.NewVCSA.Cluster | Set-VsanClusterConfiguration -HealthCheckIntervalMinutes 0 | Out-File -Append -LiteralPath $verboseLogFile


foreach ($vmhost in Get-Cluster -Server $vc -Name $config.vSphere_Deployment.NewVCSA.Cluster | Get-VMHost) {
    $luns = $vmhost | Get-ScsiLun | select CanonicalName, CapacityGB

    My-Logger "Querying ESXi host disks to create VSAN Diskgroups ..."
    foreach ($lun in $luns) {
        if(([int]($lun.CapacityGB)).toString() -eq "$($config.vSphere_Deployment.NestedESXiResources.CachingDisk)") {
            $vsanCacheDisk = $lun.CanonicalName
        }
        if(([int]($lun.CapacityGB)).toString() -eq "$($config.vSphere_Deployment.NestedESXiResources.CapacityDisk)") {
            $vsanCapacityDisk = $lun.CanonicalName
        }
    }
    My-Logger "Creating VSAN DiskGroup for $vmhost ..."
    New-VsanDiskGroup -Server $vc -VMHost $vmhost -SsdCanonicalName $vsanCacheDisk -DataDiskCanonicalName $vsanCapacityDisk | Out-File -Append -LiteralPath $verboseLogFile
}

# Exit maintanence mode in case patching was done earlier
foreach ($vmhost in Get-Cluster -Server $vc -Name $config.vSphere_Deployment.NewVCSA.Cluster | Get-VMHost) {
    if($vmhost.ConnectionState -eq "Maintenance") {
        Set-VMHost -VMhost $vmhost -State Connected -RunAsync -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
    }
}

My-Logger "Disconnecting from management vCenter Server ..."
Disconnect-VIServer -Server $vc -Confirm:$false
