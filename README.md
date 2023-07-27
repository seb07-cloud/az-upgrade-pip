# Upgrade your Azure Public Ip Addresses to Standard SKU

This PowerShell script is designed to upgrade the public IP address of a virtual machine in Azure. It is intended for use by developers who need to upgrade their virtual machines to use a Standard SKU public IP address.

Based on the following article [https://azure.microsoft.com/en-us/updates/upgrade-to-standard-sku-public-ip-addresses-in-azure-by-30-september-2025-basic-sku-will-be-retired/](https://azure.microsoft.com/en-us/updates/upgrade-to-standard-sku-public-ip-addresses-in-azure-by-30-september-2025-basic-sku-will-be-retired/)

## Prerequisites

Before running this script, you must have the following:

- Azure PowerShell module installed
- Azure account with appropriate permissions to manage virtual machines and public IP addresses

## Usage

To use this script, follow these steps:

1. Open PowerShell and navigate to the directory where the script is saved.
2. Run the script using the following command: `.\upgrade-pip.ps1`
3. The script will then stop the virtual machine, upgrade the public IP address, and restart the virtual machine.

## Parameters

This script takes the following parameters:

- Object: A System.Management.Automation.PSCustomObject that contains the necessary information to upgrade the public IP address of a virtual machine.

## Return Values

This script returns a System.Management.Automation.PSCustomObject that contains the following properties:

- SubscriptionId: The ID of the Azure subscription.
- VirtualMachine: The name of the virtual machine.
- VirtualMachineResourceGroupName: The name of the resource group that contains the virtual machine.
- Nic: The network interface card (NIC) associated with the virtual machine.
- PublicIp: The public IP address associated with the NIC.
- NicResourceGroupName: The name of the resource group that contains the NIC.
- Location: The location of the virtual machine.
- VnetName: The name of the virtual network that contains the virtual machine.
- SubnetName: The name of the subnet that contains the virtual machine.
- NetworkInterface: The network interface associated with the virtual machine.
- NetworkInterfaceConfig: The IP configuration associated with the network interface.
- Message: A message indicating the status of the upgrade process.

## License

This code is released under the MIT License. See [LICENSE](LICENSE) for details.
