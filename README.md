# Deploys a Private Link Service, Load Balancer, Cloud-Init enabled Virtual Machines in a Scale Set with port forwarding and SQL MI
[![Build Status](https://travis-ci.org/Azure/terraform-azurerm-vmss-cloudinit.svg?branch=master)](https://travis-ci.org/Azure/terraform-azurerm-vmss-cloudinit)

### Architecture Diagram
* Process flow ![alt text](https://github.com/preddy727/PrivateLinkServiceForwarderSqlMi/SQLMI.png)

This terraform module uses an existing subnet. Disable the subnet private endpoint policies using the Azure CLI command below prior to running the terraform apply.

az network vnet subnet update \ 
  --name default \ 
  --resource-group myResourceGroup \ 
  --vnet-name myVirtualNetwork \ 
  --disable-private-link-service-network-policies true 



This Terraform module deploys a Private Link Service attached to the frontend ip of a loadbancer. The load balancer is attached to a Virtual Machines Scale Set in Azure which serves as a proxy to a backend SQL MI instance. It initializes the VMs using Cloud-int for [cloud-init-enabled virtual machine images](https://docs.microsoft.com/en-us/azure/virtual-machines/linux/using-cloud-init), and returns the id of the VM scale set deployed.  

This module requires a scaleset, network and loadbalancer to be provided separately such as the "Azure/network/azurerm" and "Azure/loadbalancer/azurerm" modules.

Visit [this website](http://cloudinit.readthedocs.io/en/latest/index.html) for more information about cloud-init. Some quick tips:
- Troubleshoot logging via `/var/log/cloud-init.log`
- Relevant applied cloud configuration information can be found in the `/var/lib/cloud/instance` directory
- By default this module will create a new txt file `/tmp/terraformtest` to validate if cloud-init worked

To override the cloud-init configuration, place a file called `cloudconfig.tpl` in the root of the module directory with the cloud-init contents or update the `cloudconfig_file` variable with the location of the file containing the desired configuration.

Valid values for `vm_os_simple` are the latest versions of:
- UbuntuServer   = 16.04-LTS
- UbuntuServer14 = 14.04.5-LTS
- RHEL           = RedHat Enterprise Linux 7
- CentOS         = CentOS 7
- CoreOS         = CoreOS Stable

## Usage

```hcl
data "azurerm_resource_group" "pls_forwarder" {
  name = var.pls_forwarder_resource_group_name
}

data "azurerm_resource_group" "pe" {
  name = var.pe_resource_group_name
}

data "azurerm_resource_group" "pls_vnet_rg" {
  name = var.pls_vnet_resource_group_name
}

data "azurerm_subnet" "proxy_subnet" {
  name                 = var.proxy_subnet_name
  virtual_network_name = var.virtual_network_name
  resource_group_name  = var.pls_vnet_resource_group_name
}

data "azurerm_subnet" "pls_subnet" {
  name                 = var.pls_subnet_name
  virtual_network_name = var.virtual_network_name
  resource_group_name  = var.pls_vnet_resource_group_name
}

module "loadbalancer" {
  source              = "github.com/preddy727/terraform-azurerm-loadbalancer"
  resource_group_name = var.pls_forwarder_resource_group_name
  location            = var.location
  prefix              = "terraform-test"
  frontend_subnet_id  = data.azurerm_subnet.proxy_subnet.id
  remote_port = {
    sql = ["Tcp", "1433"]
  }
  lb_port = {
    sql = ["1433", "Tcp", "1433"]
  }
}

data "template_file" "cloudinit" {
  template = file("${path.module}/cloudconfig.tpl")
  vars = {
    sql_mi_fqdn = var.sql_mi_fqdn
  }
}

module "vmss-cloudinit" {
  source                                 = "github.com/preddy727/terraform-azurerm-vmss-cloudinit"
  network_profile                        = var.network_profile
  resource_group_name                    = var.pls_forwarder_resource_group_name
  custom_data                            = data.template_file.cloudinit.rendered
  location                               = var.location
  vm_size                                = var.vm_size
  admin_username                         = "azureuser"
  admin_password                         = "AzurePassword123456!"
  ssh_key                                = "~/.ssh/id_rsa.pub"
  nb_instance                            = var.nb_instance
  vm_os_simple                           = var.vm_os_simple
  vnet_subnet_id                         = data.azurerm_subnet.proxy_subnet.id
  load_balancer_backend_address_pool_ids = module.loadbalancer.azurerm_lb_backend_address_pool_id
}

resource "azurerm_private_link_service" "pls" {
  name                = var.pl_service
  location            = data.azurerm_resource_group.pls_forwarder.location
  resource_group_name = data.azurerm_resource_group.pls_forwarder.name

  ip_configuration {
    name               = "pls_nat"
    subnet_id          = data.azurerm_subnet.pls_subnet.id
    private_ip_address = var.pl_service_pvt_ip
  }

  load_balancer_frontend_ip_configuration {
    id = module.loadbalancer.azurerm_lb_frontend_ip_configuration[0].id
  } 
}
```

## Authors

Originally created by [David Tesar](http://github.com/dtzar)

## License

[MIT](LICENSE)
