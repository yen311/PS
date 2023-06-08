param(
    [Parameter(Mandatory=$true)]
    [string]$clientSecret,
    [Parameter(Mandatory=$true)]
    [String]$tenantId,
    [Parameter(Mandatory=$true)]
    [String]$clientId,
    [Parameter(Mandatory=$true)]
    [String]$subId,
    [Parameter(Mandatory=$true)]
    [String]$storageAccountResourceGroupName,
    [Parameter(Mandatory=$true)]
    [String]$storageAccountName,
    [Parameter(Mandatory=$true)]
    [String]$tableName
)

#authenticate to azure via service principal
$PWord = ConvertTo-SecureString -String $clientSecret -AsPlainText -Force
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $clientId, $PWord
Connect-AzAccount -ServicePrincipal -Tenant $tenantId -Credential $Credential


Write-Output 'Getting VMs...'

# Get all subscriptions
$subscriptions = Get-AzSubscription

Set-AzContext -Subscription $subId

$storageAccountResourceGroupName = $storageAccountResourceGroupName
$storageAccountName = $storageAccountName
$tableName = $tableName
$storageAccount = Get-AzStorageAccount -ResourceGroupName $storageAccountResourceGroupName -Name $storageAccountName 
$ctx = $storageAccount.Context
$storageTable = Get-AzStorageTable -Name $tableName -Context $ctx 

$totalEntities=(Get-AzTableRow -table $storageTable.CloudTable | measure).Count

# Create an array to store the output
$output = @()

# Loop through each subscription
foreach ($subscription in $subscriptions) {

    $totalEntities=(Get-AzTableRow -table $storageTable.CloudTable | measure).Count
    
    # Set the current subscription context
    Set-AzContext -Subscription $subscription.Id

    # Get the VMs in the current subscription
    $vms = Get-AzVM -status

    # Loop through each VM and display its details
    foreach ($vm in $vms) {

        #RG details
        $resourceGroup = Get-AzResourceGroup -Name $vm.ResourceGroupName

        # VM details
        $vmDetails = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -VMName $vm.Name

        $vmFamily = $vmDetails.HardwareProfile.VmSize

        $vmCpuRam =  Get-AzVMSize -VMName $vm.Name -ResourceGroupName $vm.ResourceGroupName | Where-Object {$_.Name -eq $vmFamily} | Select-Object -First 1 -Property NumberOfCores,MemoryInMB

        $vmCpu = [string]$vmCpuRam.NumberOfCores

        $vmMemory = [string]$vmCpuRam.MemoryInMB
    
        $networkProfile = $vm.NetworkProfile.NetworkInterfaces.id.Split("/")|Select -Last 1

        $IPConfig = (Get-AzNetworkInterface -Name $networkProfile).IpConfigurations.PrivateIpAddress

        $EncryptionStatus = Get-AzVMDiskEncryptionStatus -ResourceGroupName $vm.ResourceGroupName -VMName $vm.Name

        $osType = [string]$vm.StorageProfile.OsDisk.OsType

        $osVolumeEncrypted = [string]$EncryptionStatus.OsVolumeEncrypted

        try{
            $sqlinfo = Get-AzSqlVM -Name $vm.Name -ResourceGroupName $resourceGroup.ResourceGroupName -ErrorAction Stop
            $sql = [string]$sqlinfo.SqlImageSku
            $sqlversion = $sqlinfo.SqlImageOffer
        }
        catch{
            $sql = "None"
            $sqlversion = "None"
        }
        
        
        Write-Output "Subscription Name: $($subscription.Name)"
        Write-Output "Subscription ID: $($subscription.Id)"
        Write-Output "Resource Group Name: $($resourceGroup.ResourceGroupName)"
        Write-Output "Resource Group ID: $($resourceGroup.ResourceId)"
        Write-Output "Resource ID: $($vm.Id)"
        Write-Output "Name: $($vm.Name)"
        Write-Output "CPU: $($vmCpu)"
        Write-Output "Memory: $($vmMemory)"
        Write-Output "Family: $($vmFamily)"
        Write-Output "Region: $($vm.Location)"
        Write-Output "IP: $($IPConfig)"
        Write-Output "SQL: $sql"
        Write-Output "SQL Version: $sqlversion"
        Write-Output "Shutdown: $($vm.PowerState)"
        Write-Output "OS Type: $($osType)"
        Write-Output "OS Version: $($vm.StorageProfile.ImageReference.ExactVersion)"
        Write-Output "Os Volume Encrypted: $($osVolumeEncrypted)"
        Write-Output ""
        
        Add-AzTableRow `
            -table $storageTable.CloudTable `
            -partitionKey 'MyPartitionKey' `
            -rowKey $($vms.IndexOf($vm) + $totalEntities) `
            -property @{'SubscriptionName' = $subscription.Name; `
                        'SubscriptionID' = $subscription.Id; `
                        'ResourceGroupName' = $resourceGroup.ResourceGroupName; `
                        'ResourceGroupID' = $resourceGroup.ResourceId; `
                        'ResourceID' = $vm.Id; `
                        'Name' = $vm.Name; `
                        'CPU' = $vmCpu; `
                        'Memory' = $vmMemory; `
                        'Family' = $vmFamily; `
                        'Region' = $vm.Location; `
                        'IP' = $IPConfig; `
                        'SQL' = $sql; `
                        'SQLVersion' = $sqlversion; `
                        'Shutdown' = $vm.PowerState; `
                        'OSType' = $osType; `
                        'OSVersion' = $vm.StorageProfile.ImageReference.ExactVersion; `
                        'OSVolumeEncrypted' = $osVolumeEncrypted;}
        
        $output += New-Object -TypeName PSObject -Property @{'SubscriptionName' = $subscription.Name; `
                'SubscriptionID' = $subscription.Id; `
                'ResourceGroupName' = $resourceGroup.ResourceGroupName; `
                'ResourceGroupID' = $resourceGroup.ResourceId; `
                'ResourceID' = $vm.Id; `
                'Name' = $vm.Name; `
                'CPU' = $vmCpu; `
                'Memory' = $vmMemory; `
                'Family' = $vmFamily; `
                'Region' = $vm.Location; `
                'IP' = $IPConfig; `
                'SQL' = $sql; `
                'SQLVersion' = $sqlversion; `
                'Shutdown' = $vm.PowerState; `
                'OSType' = $osType; `
                'OSVersion' = $vm.StorageProfile.ImageReference.ExactVersion; `
                'OSVolumeEncrypted' = $osVolumeEncrypted;}

    }
}

# $output | Export-Csv -Path "output.csv" -NoTypeInformation
