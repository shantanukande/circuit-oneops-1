=begin
This spec has tests that validates a successfully completed oneops-azure deployment
=end

COOKBOOKS_PATH ||="/opt/oneops/inductor/circuit-oneops-1/components/cookbooks"

require 'chef'
require 'fog/azurerm'
(
  Dir.glob("#{COOKBOOKS_PATH}/azure/libraries/*.rb") +
  Dir.glob("#{COOKBOOKS_PATH}/azure_base/libraries/*.rb")
).each {|lib| require lib}
require "#{COOKBOOKS_PATH}/azuresecgroup/libraries/network_security_group.rb"

RSpec.configure do |c|
  c.filter_run_excluding :express_route_enabled => !AzureSpecUtils.new($node).is_express_route_enabled
end

describe "vm on azure" do

  before(:each) do
    @spec_utils = AzureSpecUtils.new($node)
  end

  context "resource group" do
    it "should exist" do
      rg_svc = AzureBase::ResourceGroupManager.new($node)
      exists = rg_svc.exists?

      expect(exists).to eq(true)
    end
  end

  context "vm" do
    it "should exist" do
      credentials = @spec_utils.get_azure_creds
      virtual_machine_lib = AzureCompute::VirtualMachine.new(credentials)

      resource_group_name = @spec_utils.get_resource_group_name
      server_name = @spec_utils.get_server_name
      vm = virtual_machine_lib.get(resource_group_name, server_name)

      expect(vm).not_to be_nil
      expect(vm.name).to eq(server_name)
    end

    context "compute size" do
      it "should exist" do
        credentials = @spec_utils.get_azure_creds
        virtual_machine_lib = AzureCompute::VirtualMachine.new(credentials)

        resource_group_name = @spec_utils.get_resource_group_name
        server_name = @spec_utils.get_server_name
        vm = virtual_machine_lib.get(resource_group_name, server_name)

        default_size_mapping = {"XS"=>"Standard_A0","S"=>"Standard_A1","M"=>"Standard_A2","L"=>"Standard_A3","XL"=>"Standard_A4","XXL"=>"Standard_A5","3XL"=>"Standard_A6","4XL"=>"Standard_A7","S-CPU"=>"Standard_D1","M-CPU"=>"Standard_D2","L-CPU"=>"Standard_D3","XL-CPU"=>"Standard_D4","8XL-CPU"=>"Standard_D11","9XL-CPU"=>"Standard_D12","10XL-CPU"=>"Standard_D13","11XL-CPU"=>"Standard_D14","S-MEM"=>"Standard_DS1","M-MEM"=>"Standard_DS2","L-MEM"=>"Standard_DS3","XL-MEM"=>"Standard_DS4","8XL-MEM"=>"Standard_DS11","9XL-MEM"=>"Standard_DS12","10XL-MEM"=>"Standard_DS13","11XL-MEM"=>"Standard_DS14"}
        expect(vm.vm_size).to eq(default_size_mapping[$node[:workorder][:rfcCi][:ciAttributes][:size]])
      end
    end

    context "instance type" do
      it "should exist" do
        credentials = @spec_utils.get_azure_creds
        virtual_machine_lib = AzureCompute::VirtualMachine.new(credentials)

        resource_group_name = @spec_utils.get_resource_group_name
        server_name = @spec_utils.get_server_name
        vm = virtual_machine_lib.get(resource_group_name, server_name)
        compute_instance = (vm.offer+"-"+vm.sku.to_s).downcase
        expect(compute_instance).to eq($node[:workorder][:payLoad][:os][0][:ciAttributes]['ostype'].downcase)
      end
    end

    it "has oneops org and assembly tags" do
      tags_from_work_order = Utils.get_resource_tags($node)

      credentials = @spec_utils.get_azure_creds
      virtual_machine_lib = AzureCompute::VirtualMachine.new(credentials)
      vm = virtual_machine_lib.get(@spec_utils.get_resource_group_name, @spec_utils.get_server_name)

      tags_from_work_order.each do |key, value|
        expect(vm.tags).to include(key => value)
      end
    end
  end

  context "Fault and Update domain" do
    it "Fault and Update domain returns" do

      credentials = @spec_utils.get_azure_creds
      virtual_machine_lib = AzureCompute::VirtualMachine.new(credentials)
      resource_group_name = @spec_utils.get_resource_group_name
      server_name = @spec_utils.get_server_name
      vm = virtual_machine_lib.get(resource_group_name, server_name)
      expect(vm.platform_fault_domain).not_to be_nil
      expect(vm.platform_update_domain).not_to be_nil
    end
  end

  context "os disk" do
    it "should exist" do
      credentials = @spec_utils.get_azure_creds
      virtual_machine_lib = AzureCompute::VirtualMachine.new(credentials)
      vm = virtual_machine_lib.get(@spec_utils.get_resource_group_name, @spec_utils.get_server_name)

      expect(vm.os_disk_name).not_to be_nil
      expect(vm.os_disk_name).not_to eq('')

      azure_compute_service = Fog::Compute::AzureRM.new(credentials)
      os_disk = azure_compute_service
                    .managed_disks
                    .get(@spec_utils.get_resource_group_name, vm.os_disk_name)


      expect(os_disk).not_to be_nil
      expect(os_disk.provisioning_state).to eq('Succeeded')
    end

    it 'is managed' do
      credentials = @spec_utils.get_azure_creds
      virtual_machine_lib = AzureCompute::VirtualMachine.new(credentials)
      vm = virtual_machine_lib.get(@spec_utils.get_resource_group_name, @spec_utils.get_server_name)

      azure_compute_service = Fog::Compute::AzureRM.new(credentials)
      os_disk = azure_compute_service
                    .managed_disks
                    .get(@spec_utils.get_resource_group_name, vm.os_disk_name)

      expect(vm.storage_account_name).to be_nil
      expect(os_disk).to be_a_kind_of(Fog::Compute::AzureRM::ManagedDisk)
      expect(os_disk.creation_data.storage_account_id).to be_nil
    end

    it "has oneops org and assembly tags" do
      tags_from_work_order = Utils.get_resource_tags($node)

      credentials = @spec_utils.get_azure_creds
      virtual_machine_lib = AzureCompute::VirtualMachine.new(credentials)
      vm = virtual_machine_lib.get(@spec_utils.get_resource_group_name, @spec_utils.get_server_name)

      azure_compute_service = Fog::Compute::AzureRM.new(credentials)
      os_disk = azure_compute_service
                    .managed_disks
                    .get(@spec_utils.get_resource_group_name, vm.os_disk_name)

      tags_from_work_order.each do |key, value|
        expect(os_disk.tags).to include(key => value)
      end
    end
  end

  context "nic" do
    it "uses predefined virtual network when express route is enabled", :express_route_enabled => true do

      @spec_utils.set_attributes_on_node_required_for_vm_manager
      vm_manager = AzureCompute::VirtualMachineManager.new($node)
      predefined_vnet = vm_manager.compute_service['network']

      credentials = @spec_utils.get_azure_creds
      virtual_machine_lib = AzureCompute::VirtualMachine.new(credentials)
      vm = virtual_machine_lib.get(@spec_utils.get_resource_group_name, @spec_utils.get_server_name)
      primary_nic_id = vm.network_interface_card_ids[0]
      primary_nic_name = Hash[*(primary_nic_id.split('/'))[1..-1]]['networkInterfaces']

      nic_svc = AzureNetwork::NetworkInterfaceCard.new(credentials)
      nic_svc.ci_id = $node['workorder']['rfcCi']['ciId']
      nic_svc.rg_name = @spec_utils.get_resource_group_name
      nic = nic_svc.get(primary_nic_name)

      nic_subnet_vnet = Hash[*(nic.subnet_id.split('/'))[1..-1]]['virtualNetworks']
      expect(nic_subnet_vnet).to eq(predefined_vnet)
    end

    it "has oneops org and assembly tags" do
      tags_from_work_order = Utils.get_resource_tags($node)

      nic_svc = AzureNetwork::NetworkInterfaceCard.new( @spec_utils.get_azure_creds)
      nic_svc.ci_id = $node['workorder']['rfcCi']['ciId']
      nic_svc.rg_name = @spec_utils.get_resource_group_name
      nic_name = Utils.get_component_name('nic', nic_svc.ci_id)
      nic = nic_svc.get(nic_name)

      tags_from_work_order.each do |key, value|
        expect(nic.tags).to include(key => value)
      end

    end
  end

end