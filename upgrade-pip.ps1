function Get-PublicIps {
  [CmdletBinding()]
  param (
    [string]$skuName = "Basic"
  )

  $subscriptions = Get-AzSubscription
  $context = Get-AzContext
  $returnObject = @()

  # Get all public IPs in the subscription
  foreach ($subscription in $subscriptions) {
    Set-AzContext -SubscriptionId $subscription.Id | Out-Null

    $pips = Get-AzPublicIpAddress | Where-Object { $_.Sku.Name -eq $skuName }

    foreach ($pip in $pips) {

      # Get corresponding network interface
      $nic = Get-AzNetworkInterface | Where-Object { $_.IpConfigurations.PublicIpAddress.Id -eq $pip.Id }
      
      # Get Networkinterface Config
      $nicConfig = Get-AzNetworkInterfaceIpConfig -Name $nic.IpConfigurations.Name -NetworkInterface $nic

      # Get VM
      $vm = Get-AzVM -Status | Where-Object { $_.NetworkProfile.NetworkInterfaces.Id -eq $nic.Id }

      # Get VM Nic Name
      $vmnic = ($vm.NetworkProfile.NetworkInterfaces.id).Split('/')[-1]
      $vmnicinfo = Get-AzNetworkInterface -Name $vmnic

      # If not deallocated, add to return object
      if ($vm.PowerState -ne "VM deallocated") {
        $returnObject += New-Object -TypeName PSCustomObject -Property @{
          SubscriptionId                  = $subscription.Id
          PublicIp                        = $pip
          PublicIpAddress                 = $pip.IpAddress
          PublicIpId                      = $pip.Id
          PublicIpConfig                  = $pip.IpConfiguration
          NetworkInterface                = $nic
          NetworkInterfaceName            = ($vm.NetworkProfile.NetworkInterfaces.Id).Split('/')[-1]
          NicResourceGroupName            = $nic.ResourceGroupName
          NetworkInterfaceConfig          = $nicConfig
          VirtualMachine                  = $vm
          VirtualMachineResourceGroupName = $vm.ResourceGroupName
          VnetName                        = $((($vmnicinfo.IpConfigurations.subnet.id).Split('/'))[-3])
          SubnetName                      = $((($vmnicinfo.IpConfigurations.subnet.id).Split('/'))[-1])
          Location                        = $vm.Location
        }
      }
    }
  }
  # Set context back to original
  Set-AzContext -SubscriptionId $context.Subscription.Id | Out-Null
  return $returnObject
}

function Stop-VirtualMachine {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [System.Object]$Object
  )

  $returnObject = @()

  # Validate the parameter System.Management.Automation.PSCustomObject
  if ($object.GetType().Name -ne "PSCustomObject") {
    throw "Parameter must be of type System.Management.Automation.PSCustomObject"
  }

  # Save Context and set initial context at the end
  $context = Get-AzContext
  
  foreach ($obj in $object) {

    if ($object.SubscriptionId) {
      $context = Get-AzContext
      if ($obj.SubscriptionId -ne $context.Subscription.Id) {
        Set-AzContext -SubscriptionId $obj.SubscriptionId
      }

      try {
        Write-Host "Deallocating virtual machine $($obj.VirtualMachine.Name) in resource group $($obj.VirtualMachineResourceGroupName)" -ForegroundColor Yellow
        Stop-AzVM -ResourceGroupName $obj.VirtualMachineResourceGroupName -Name $obj.VirtualMachine.Name -Force -AsJob | Out-Null  

        while ((Get-AzVM -Status | Where-Object { $_.NetworkProfile.NetworkInterfaces.Id -eq $obj.NetworkInterface.Id }).PowerState -ne "VM deallocated") {
          Start-Sleep -Seconds 5
        }

        $returnObject += New-Object -TypeName PSCustomObject -Property @{
          SubscriptionId                  = $obj.SubscriptionId
          VirtualMachine                  = $obj.VirtualMachine
          VirtualMachineResourceGroupName = $obj.VirtualMachineResourceGroupName
          Nic                             = $obj.NetworkInterface
          PublicIp                        = $obj.PublicIp
          NicResourceGroupName            = $obj.NicResourceGroupName
          Location                        = $obj.Location
          VnetName                        = $obj.VnetName
          SubnetName                      = $obj.SubnetName
          NetworkInterface                = $obj.NetworkInterface
          NetworkInterfaceConfig          = $obj.NetworkInterfaceConfig
          Message                         = "Virtual machine deallocated"
        }

        Write-Host "Virtual machine $($obj.VirtualMachine.Name) deallocated" -ForegroundColor Green
      }
      catch {
        # Add error to return object
        $returnObject += New-Object -TypeName PSCustomObject -Property @{
          Message = $_.Exception.Message
        }
      }
    }
    else {
      throw "No subscription ID provided"
    }
  }
  # Set context back to original
  Set-AzContext -SubscriptionId $context.Subscription.Id | Out-Null
  return $returnObject
}

function Upgrade-Pip {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [System.Object]$Object
  )
  
  $context = Get-AzContext
  $returnObject = @()

  # Validate the parameter System.Management.Automation.PSCustomObject
  if ($object.GetType().Name -ne "PSCustomObject") {
    throw "Parameter must be of type System.Management.Automation.PSCustomObject"
  }

  foreach ($obj in $object) {

    if ($obj.Message -ne "Virtual machine deallocated") {
      throw "Virtual machine must be deallocated before upgrading public IP"
    }
    else {
      Write-Host "Virtual machine deallocated" -ForegroundColor Green

      Set-AzContext -SubscriptionId $obj.SubscriptionId

      try {
        Write-Host "Upgrading public IP $($obj.PublicIp.Name) in resource group $($obj.NicResourceGroupName)" -ForegroundColor Yellow

        # Disassociate public IP from network interface
        Set-AzNetworkInterfaceIpConfig -Name $obj.NetworkInterfaceConfig.Name -NetworkInterface $obj.NetworkInterface -PublicIpAddress $null | Out-Null
        Set-AzNetworkInterface -NetworkInterface $obj.NetworkInterface | Out-Null

        # Upgrade public IP
        $pip = Get-AzPublicIpAddress -Name $obj.PublicIp.Name -ResourceGroupName $obj.NicResourceGroupName
        $pip.Sku.Name = "Standard"
        $pip | Set-AzPublicIpAddress | Out-Null

        $returnObject += New-Object -TypeName PSCustomObject -Property @{
          SubscriptionId    = $obj.SubscriptionId
          PublicIp          = $obj.PublicIp
          ResourceGroupName = $obj.NicResourceGroupName
          Message           = "Public IP upgraded"
        }

        Write-Host "Public IP $($obj.PublicIp.Name) upgraded, now reassociating to Virtual Machine $($obj.VirtualMachine.Name)" -ForegroundColor Green
        Set-AzNetworkInterfaceIpConfig -Name $obj.NetworkInterfaceConfig.Name -NetworkInterface $obj.NetworkInterface -PublicIpAddress $obj.PublicIp | Out-Null
        Set-AzNetworkInterface -NetworkInterface $obj.NetworkInterface | Out-Null

        $returnObject | Add-Member -MemberType NoteProperty -Name "Success" -Value "Public IP upgraded and reassociated to Virtual Machine"

        # if successful, start virtual machine
        Start-AzVM -ResourceGroupName $obj.VirtualMachineResourceGroupName -Name $obj.VirtualMachine.Name -AsJob | Out-Null
      }
      catch {
        # Add error to return object
        $returnObject += New-Object -TypeName PSCustomObject -Property @{
          Message = $_.Exception.Message
        }
      }
    }
  }
  Set-AzContext -SubscriptionId $context.Subscription.Id | Out-Null
  return $returnObject
}

Get-PublicIps | Stop-VirtualMachine | Upgrade-Pip