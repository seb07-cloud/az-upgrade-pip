param (
  [Parameter(Mandatory = $false)]
  [string]$subscriptionId
)

if ($subscriptionId) {
  Set-AzContext -SubscriptionId $subscriptionId
  $subscriptions = $subscriptionId
}
else {
  Write-Host "No subscription ID provided, interating over all Subscriptions" -ForegroundColor Yellow
  $subscriptions = Get-AzSubscription
}

foreach ($subscription in $subscriptions) {
  
  # Get all public IPs in the subscription
  $publicIPs = Get-AzPublicIpAddress | Where-Object { $_.Sku.Name -eq "Basic" } 

  if ($publicIPs.Count -gt 0) {

    # Deallocate Basic Public IPs
    foreach ($ip in $publicIPs) {

      # New PSCustomObject to store all vm information
      $vmInfo = New-Object -TypeName PSCustomObject -Property @{
        Vm                = $null
        ResourceGroupName = $null
        Vnet              = $null
        Subnet            = $null
        IpConfig          = $null
        Nic               = $null
        Id                = $null
      }

      # Get the associated network interface
      $nic = Get-AzNetworkInterface | Where-Object { $_.IpConfigurations.PublicIpAddress.Id -eq $ip.Id }
      $vmInfo.Nic = $nic
      
      $vmInfo.IpConfig = Get-AzNetworkInterfaceIpConfig -Name $nic.IpConfigurations.Name -NetworkInterface $nic

      # Deallocate the virtual machine
      $vmInfo.Vm = Get-AzVM -Status | Where-Object { $_.NetworkProfile.NetworkInterfaces.Id -eq $nic.Id }
      $vmInfo.ResourceGroupName = $vm.ResourceGroupName

      # Parse out the Network Interface name
      $vmnic = ($vm.NetworkProfile.NetworkInterfaces.id).Split('/')[-1]
      $vmnicinfo = Get-AzNetworkInterface -Name $vmnic

      # Get Vnet and Subnet information
      $vmInfo.Vnet = $((($vmnicinfo.IpConfigurations.subnet.id).Split('/'))[-3])
      $vmInfo.Subnet = $((($vmnicinfo.IpConfigurations.subnet.id).Split('/'))[-1])

      if ($vm.PowerState -eq "VM running") {
        Write-Host "Deallocating virtual machine $($vm.Name) in resource group $($vm.ResourceGroupName)"
        Stop-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Force -AsJob | Out-Null

        while ((Get-AzVM -Status | Where-Object { $_.NetworkProfile.NetworkInterfaces.Id -eq $nic.Id }).PowerState -ne "VM deallocated") {
          Write-Host "Waiting for virtual machine $($vm.Name) to deallocate" -ForegroundColor Yellow
          Start-Sleep -Seconds 5
        }
      } 

      Write-Host "VM $($vm.Name) deallocated" -ForegroundColor Green

      try {

        # Deallocate the public IP
        Write-Host "Deallocating public IP $($ip.Name) in resource group $($ip.ResourceGroupName) associated to virtual machine $($vm.Name)" -ForegroundColor Yellow
  
        # Remove the public IP from the network interface
        $nic.IpConfigurations.PublicIpAddress.Id = $null
        Set-AzNetworkInterface -NetworkInterface $nic
  
        Write-Host "Public IP $($ip.Name) already deallocated" -ForegroundColor Green
        Set-AzNetworkInterface -NetworkInterface $nic
        
        # Deallocate the public IP
        Write-Host "Upgrading public IP $($ip.Name) in resource group $($ip.ResourceGroupName)"
        $ip.Sku.Name = 'Standard'
        Set-AzPublicIpAddress -PublicIpAddress $ip

        # Re-associate the public IP to the network interface
        Write-Host "Public IP $($ip.Name) upgraded to $($ip.Sku.Name) in resource group $($ip.ResourceGroupName)" -ForegroundColor Green
        Set-AzNetworkInterfaceIpConfig -Name $vmInfo.IpConfig.Name -NetworkInterface $vmInfo.Nic -PublicIpAddress $ip
        Set-AzNetworkInterface -NetworkInterface $vmInfo.Nic

        # Start the virtual machine
        Start-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -AsJob | Out-Null
        # Output completion message
        Write-Output "Upgrade procedure complete!"
      }
      catch {
        $_.Exception.Message
        Write-Host "Failed to upgrade public IP $($ip.Name) in resource group $($ip.ResourceGroupName)" -ForegroundColor Red
      }
    }
  }
}
