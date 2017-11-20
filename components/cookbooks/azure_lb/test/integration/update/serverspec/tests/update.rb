COOKBOOKS_PATH = "/opt/oneops/inductor/circuit-oneops-1/components/cookbooks"

require 'fog/azurerm'
require "#{COOKBOOKS_PATH}/azure_lb/libraries/load_balancer.rb"
require "#{COOKBOOKS_PATH}/azure_base/libraries/utils.rb"
require "#{COOKBOOKS_PATH}/azure/libraries/virtual_network.rb"

#load spec utils
require "#{COOKBOOKS_PATH}/azure_base/test/integration/azure_spec_utils"
require "#{COOKBOOKS_PATH}/azure_base/test/integration/azure_lb_spec_utils"

describe 'azure lb' do
  before(:each) do
    @spec_utils = AzureLBSpecUtils.new($node)
  end


  it 'shouldnt change ip after update' do

    creds = @spec_utils.get_azure_creds
    lb_service = @spec_utils.get_service
    public_ip = nil
    lb_name = @spec_utils.get_lb_name
    subscription_id = lb_service[:subscription]
    resource_group_name = @spec_utils.get_resource_group_name
    platform_name = $node['workorder']['box']['ciName']
    environment_name = $node['workorder']['payLoad']['Environment'][0]['ciName']
    env_name = environment_name.gsub(/-/, '').downcase
    location = @spec_utils.get_location

    #get the ip of lb when it is first created
    lb_svc = AzureNetwork::LoadBalancer.new(creds)
    existing_lb = lb_svc.get(resource_group_name, lb_name)
    existing_lb_ip = existing_lb.frontend_ip_configurations[0].private_ipaddress
    #puts existing_lb.inspect



    #create the lb again
    master_rg = lb_service[:resource_group]

    vnet_svc = AzureNetwork::VirtualNetwork.new(creds)
    vnet_svc.name = lb_service[:network]
    vnet = vnet_svc.get(master_rg)

    subnets = vnet.subnets
    subnet = vnet_svc.get_subnet_with_available_ips(subnets, true)

    # Frontend IP Config
    frontend_ipconfig_name = 'LB-FrontEndIP'
    frontend_ipconfig = AzureNetwork::LoadBalancer.create_frontend_ipconfig(frontend_ipconfig_name, public_ip, subnet)
    frontend_ipconfig_id = "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group_name}/providers/Microsoft.Network/loadBalancers/#{lb_name}/frontendIPConfigurations/#{frontend_ipconfig_name}"
    frontend_ipconfigs = []
    frontend_ipconfigs.push(frontend_ipconfig)

    # Backend Address Pool
    backend_address_pool_name = 'LB-BackEndAddressPool'
    backend_address_pool_id = "/subscriptions/#{subscription_id}/resourceGroups/#{resource_group_name}/providers/Microsoft.Network/loadBalancers/#{lb_name}/backendAddressPools/#{backend_address_pool_name}"

    backend_address_pools = []
    backend_address_pool_ids = []
    backend_address_pools.push(backend_address_pool_name)
    backend_address_pool_ids.push(backend_address_pool_id)

    # ECV/Probes
    probes = @spec_utils.get_probes

    # Listeners/LB Rules
    lb_rules = @spec_utils.get_loadbalancer_rules(subscription_id, resource_group_name, lb_name, env_name, platform_name, probes, frontend_ipconfig_id, backend_address_pool_id)

    # Inbound NAT Rules
    compute_natrules = []
    nat_rules = []
    @spec_utils.get_compute_nat_rules(frontend_ipconfig_id, nat_rules, compute_natrules)

    # Configure LB properties
    tags = Utils.get_resource_tags($node)
    load_balancer = AzureNetwork::LoadBalancer.get_lb(resource_group_name, lb_name, location, frontend_ipconfigs, backend_address_pools, lb_rules, nat_rules, probes, tags)

    # Create LB
    lb = lb_svc.create_update(load_balancer)
    lb_ip = lb.frontend_ip_configurations[0].private_ipaddress

    expect(lb_ip).to eq(existing_lb_ip)

  end
end