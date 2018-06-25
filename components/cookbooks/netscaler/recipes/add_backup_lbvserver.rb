#
# Cookbook Name:: netscaler
# Recipe:: add_lbvserver
#
# Copyright 2016, Walmart Stores, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# cleanup old ones if they change vport or vprotocol (name changes)
node.backup_cleanup_loadbalancers.each do |lb|
  netscaler_lbvserver lb[:name] do
    connection node.ns_conn
    action :delete
  end
end



lbmethod = node.workorder.rfcCi.ciAttributes.lbmethod.upcase

# use previous dns_record attr for ip of cloud-level lb only if cloud vips were previously created
ip = nil
if node.workorder.rfcCi.ciAttributes.has_key?("dns_record") &&
    node.workorder.rfcCi.ciBaseAttributes.has_key?("create_cloud_level_vips") &&
    node.workorder.rfcCi.ciBaseAttributes.create_cloud_level_vips == "true"
  ip = node.workorder.rfcCi.ciAttributes.dns_record
end

# remove lbgroup if turned disabled
if node.workorder.rfcCi.has_key?("ciBaseAttributes") &&
    node.workorder.rfcCi.ciBaseAttributes.has_key?("enable_lb_group") &&
    ((node.workorder.rfcCi.ciBaseAttributes.enable_lb_group == 'true' &&
        node.workorder.rfcCi.ciAttributes.enable_lb_group == 'false') ||
        (node.workorder.rfcCi.ciBaseAttributes.has_key?("stickiness") &&
            node.workorder.rfcCi.ciBaseAttributes.stickiness == 'true' &&
            node.workorder.rfcCi.ciAttributes.stickiness == 'false'))

  include_recipe "netscaler::backup_delete_lb_group"
end

cloud_level_ip = nil
dc_level_ip = nil

node.set["ns_backup_lbvserver_ip"] = ""
ip = nil
port = '0'

node.backup_dcloadbalancers.each do |lb|


  # clear old az
  if node.has_key?("ns_conn_prev")

    Chef::Log.info("removing lb from previous az: "+
                       node.workorder.rfcCi.ciAttributes.availability_zone + "  Will be added to: "+
                       node.workorder.rfcCi.ciAttributes.required_availability_zone)

    n = netscaler_lbvserver lb[:name] do
      connection node.ns_conn_prev
      action :nothing
    end
    n.run_action(:delete)

  end

  n = netscaler_lbvserver lb[:name] do
    port port
    servicetype lb[:vprotocol]
    ipv46 ip
    lbmethod lbmethod
    stickiness node.workorder.rfcCi.ciAttributes.stickiness
    persistence_type node.workorder.rfcCi.ciAttributes.persistence_type
    connection node.ns_conn
    action :nothing
  end
  n.run_action(:backup_create)
  backup_dc_level_ip = nil

end

lbs = [] + node.backup_dcloadbalancers
node.set["backuploadbalancers"] = lbs