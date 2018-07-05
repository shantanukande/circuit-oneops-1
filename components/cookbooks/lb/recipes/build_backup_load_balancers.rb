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

cloud_name = node.workorder.cloud.ciName
cloud_service = nil
dns_service = nil

lb_service_type = node.lb.lb_service_type

exit_with_error "#{lb_service_type} service not found. either add it or change service type" if !node.workorder.services.has_key?("#{lb_service_type}")

if !node.workorder.services["#{lb_service_type}"].nil? &&
    !node.workorder.services["#{lb_service_type}"][cloud_name].nil?

  cloud_service = node.workorder.services["#{lb_service_type}"][cloud_name]
  dns_service = node.workorder.services["dns"][cloud_name]

end

if cloud_service.nil? || dns_service.nil?
  Chef::Log.error("missing cloud service. services: "+node.workorder.services.inspect)
  exit 1
end

cloud_dns_id = cloud_service[:ciAttributes][:cloud_dns_id]
env_name = node.workorder.payLoad.Environment[0]["ciName"]
asmb_name = node.workorder.payLoad.Assembly[0]["ciName"]
org_name = node.workorder.payLoad.Organization[0]["ciName"]
dns_zone = dns_service[:ciAttributes][:zone]

dc_dns_zone = ""
remote_dc_dns_zone = ""
if cloud_service[:ciAttributes].has_key?("gslb_site_dns_id")
  dc_dns_zone = cloud_service[:ciAttributes][:gslb_site_dns_id]+"."
  remote_dc_dns_zone = cloud_service[:ciAttributes][:gslb_site_dns_id]+"-remote."
end
dc_dns_zone += dns_service[:ciAttributes][:zone]
remote_dc_dns_zone += dns_service[:ciAttributes][:zone]

ci = {}
if node.workorder.has_key?("rfcCi")
  ci = node.workorder.rfcCi
else
  ci = node.workorder.ci
end


def get_ns_service_type(cloud_service_type, service_type)
  case cloud_service_type
    when "cloud.service.Netscaler" , "cloud.service.F5-bigip"

      case service_type.upcase
        when "HTTPS"
          service_type = "SSL"
      end

  end
  return service_type.upcase
end

platform = node.workorder.box
platform_name = node.workorder.box.ciName

# env-platform.glb.domain.domain.domain-servicetype_tcp[port]-lb
# d1-pricing.glb.dev.x.com-HTTP_tcp80-lb


# skip deletes if other active clouds for same dc
has_other_cloud_in_dc_active = false
if node.workorder.payLoad.has_key?("primaryactiveclouds")
  node.workorder.payLoad["primaryactiveclouds"].each do |lb_service|
    if lb_service[:ciAttributes][:gslb_site_dns_id] == cloud_service[:ciAttributes][:gslb_site_dns_id] &&
        lb_service[:nsPath] != cloud_service[:nsPath]
      has_other_cloud_in_dc_active = true
      Chef::Log.info("active cloud in same dc: "+lb_service[:nsPath].split("/").last)
    end
  end
end

backup_dcloadbalancers = Array.new
backup_cleanup_loadbalancers = Array.new

(node[:workorder].has_key?('config') && node[:workorder][:config].has_key?('backupvserver'))   ? (backupvserver_flag = node[:workorder][:config][:backupvserver])      : (backupvserver_flag = 'false')
(node[:workorder].has_key?('config') && node[:workorder][:config].has_key?('DC_Backupvserver'))   ? (dc_backvserver_list = node[:workorder][:config][:DC_Backupvserver])      : (dc_backvserver_list = nil)
Chef::Log.debug("backupvserver_flag : #{backupvserver_flag}")
Chef::Log.debug("DC List : #{dc_backvserver_list}")

enaled_backupvserver = false
if backupvserver_flag.to_s.downcase == "true"
  unless dc_backvserver_list.nil? || dc_backvserver_list.empty?
    dc_backvserver_list.split(",").each do |dc|
      if cloud_name.include? dc
        enaled_backupvserver = true
        break
      end
    end
  end
end


# build backup_load-balancers from listeners
listeners = JSON.parse(ci[:ciAttributes][:listeners])

# map for iport to node port
override_iport_map = {}
node.workorder.payLoad.DependsOn.each do |dep|
  if dep['ciClassName'] =~ /Container/
    JSON.parse(dep['ciAttributes']['node_ports']).each_pair do |internal_port,external_port|
      override_iport_map[internal_port] = external_port
    end
    puts "override_iport_map: #{override_iport_map.inspect}"
  end
end

listeners.each do |l|

  acl = ''
  lb_attrs = l.split(" ")
  vproto = lb_attrs[0]
  vport = lb_attrs[1]
  if vport.include?(':')
    vport_parts = vport.split(':')
    vport = vport_parts[0]
    acl = vport_parts[1]
  end
  iproto = lb_attrs[2]
  iport = lb_attrs[3]

  if override_iport_map.has_key?(iport)
    Chef::Log.info("using container PAT: #{iport} to #{override_iport_map[iport]}")
    iport = override_iport_map[iport]
  end

  # Get the service types
  iprotocol = get_ns_service_type(cloud_service[:ciClassName],iproto)
  vprotocol = get_ns_service_type(cloud_service[:ciClassName],vproto)

  sg_name = [env_name, platform_name, cloud_name, iport, ci["ciId"].to_s, "svcgrp"].join("-")
  backup_dc_lb_name = ["testvip", platform_name, env_name, asmb_name, org_name, dc_dns_zone].join(".") +
      '-'+vprotocol+"_"+vport+"tcp-" + platform[:ciId].to_s + "-lb"
  backup_dc_lb = {
      :name => backup_dc_lb_name,
      :iport => iport,
      :vport => vport,
      :acl => acl,
      :sg_name => sg_name,
      :vprotocol => vprotocol,
      :iprotocol => iprotocol
  }

  backup_dc_lb[:is_backup_lbvserver] = true

  if node.workorder.cloud.ciAttributes.has_key?("priority") &&
      node.workorder.cloud.ciAttributes.priority.to_i != 1

    backup_dc_lb[:is_secondary] = true

  end

  if node.workorder.rfcCi.rfcAction == "delete" &&
      has_other_cloud_in_dc_active
    Chef::Log.info("skipping delete of backup dc vip")
  else
    if enaled_backupvserver || node.workorder.rfcCi.rfcAction == "delete"
      backup_dcloadbalancers.push(backup_dc_lb)
    else
      backup_cleanup_loadbalancers.push(backup_dc_lb)
    end
  end
end


# clean-up old lbvservers
listeners_old = []
if ci.has_key?("ciBaseAttributes") &&
    ci[:ciBaseAttributes].has_key?("listeners")

  listeners_old = JSON.parse(ci[:ciBaseAttributes][:listeners])
end

listeners_old.each do |ol|

  lb_attrs_old = ol.split()
  vproto_old = lb_attrs_old[0]
  vport_old = lb_attrs_old[1]
  if vport_old.include?(':')
    vport_parts = vport_old.split(':')
    vport_old = vport_parts[0]
    acl_old = vport_parts[1]
  end
  iproto_old = lb_attrs_old[2]
  iport_old = lb_attrs_old[3]

  vprotocol_old = get_ns_service_type(cloud_service[:ciClassName],vproto_old)

  sg_name = [env_name, platform_name, cloud_name, iport_old, ci["ciId"].to_s, "svcgrp"].join("-")

  backup_dc_lb_name = ["testvip", platform_name, env_name, asmb_name, org_name, dc_dns_zone].join(".") +
      '-'+vprotocol_old+"_"+vport_old+"tcp-" + platform[:ciId].to_s + "-lb"

  dc_lb_name = [platform_name, env_name, asmb_name, org_name, dc_dns_zone].join(".") +
      '-'+vprotocol_old+"_"+vport_old+"tcp-" + platform[:ciId].to_s + "-lb"
  found = false

  backup_dcloadbalancers.each do |l|
    if l[:name] == backup_dc_lb_name
      found = true
      break
    end
  end

  if !found
    backup_dc_lb = {
        :name => backup_dc_lb_name,
        :vport => vport_old,
        :acl => acl_old,
        :sg_name => sg_name,
        :vprotocol => vprotocol_old
    }

    backup_cleanup_loadbalancers.push(backup_dc_lb)
  end

end


node.set["backup_dcloadbalancers"] = backup_dcloadbalancers
node.set["backup_cleanup_loadbalancers"] = backup_cleanup_loadbalancers

if Chef::Log.level == :debug
  Chef::Log.info("level: #{Chef::Log.level}")
  Chef::Log.info("backup_dcloadbalancers: #{backup_dcloadbalancers.inspect}")
  Chef::Log.info("backup_cleanup_loadbalancers: #{backup_cleanup_loadbalancers.inspect}")
end