require 'pp'
require 'excon'
require "#{COOKBOOKS_PATH}/netscaler/test/integration/netscaler_spec_utils"

cloud_name = $node['workorder']['cloud']['ciName']
lb_service_type = $node['lb']['lb_service_type']
gslb_site_dns_id = nil
ciId = $node['workorder']['box']['ciId']
cloud_service = nil

if !$node['workorder']['services'][lb_service_type].nil? &&
    !$node['workorder']['services'][lb_service_type][cloud_name].nil?

  cloud_service = $node['workorder']['services'][lb_service_type][cloud_name]
  gslb_site_dns_id = cloud_service['ciAttributes']['gslb_site_dns_id']
  dns_service = $node['workorder']['services']['dns'][cloud_name]

end

dns_zone = dns_service['ciAttributes']['zone']

if !$node['workorder'].has_key?("actionName")
  metadata = $node['workorder']['payLoad']['RequiresComputes'][0]['ciBaseAttributes']['metadata'].nil? ?  $node['workorder']['payLoad']['RequiresComputes'][0]['ciAttributes']['metadata'] :  $node['workorder']['payLoad']['RequiresComputes'][0]['ciBaseAttributes']['metadata']
  metadata_obj = JSON.parse(metadata)
  org = metadata_obj['organization']
  assembly = metadata_obj['assembly']
  platform = metadata_obj['platform']
  env = metadata_obj['environment']
end

vsvc_vport = nil
servicetype = nil

if $node['workorder']['rfcCi'].has_key?('ciAttributes') &&
    $node['workorder']['rfcCi']['ciAttributes'].has_key?('listeners')

  JSON.parse($node['workorder']['rfcCi']['ciAttributes']['listeners']).each do |listener|
    servicetype = listener.split(" ")[2].upcase
    servicetype = "SSL" if servicetype == "HTTPS"
    vservicetype = listener.split(" ")[0].upcase
    vservicetype = "SSL" if vservicetype == "HTTPS"
    vsvc_vport = vservicetype+"_"+listener.split(" ")[1]
  end

end

lb_name = nil
if !$node['workorder'].has_key?("actionName")
  lb_name = [platform, env, assembly, org, gslb_site_dns_id, dns_zone].join(".") + '-'+vsvc_vport+"tcp" +'-' + ciId.to_s + "-lb"
else
  if $node['workorder']['rfcCi']['ciAttributes'].has_key?("vnames")
    vnames_map = JSON.parse($node['workorder']['rfcCi']['ciAttributes']['vnames'])
  end
  vnames_map.keys.each do |key|
    if key =~ /#{gslb_site_dns_id}/
      lb_name = key
    end
  end
end

netscalar_spec_utils = NetscalerSpecUtils.new($node)
netscalar_spec_utils.get_connection
conn = $node['ns_conn']

resp_obj = JSON.parse(conn.request(
    :method=>:get,
    :path=>"/nitro/v1/config/lbvserver/#{lb_name}").body)

exists = resp_obj["message"] =~ /Done/ ? true : false

context "lbserver" do
  it "should exist" do
    expect(exists).to eq(true)
  end
end

if exists
  lbip = resp_obj["lbvserver"][0]["ipv46"]
  lbservicetype = resp_obj["lbvserver"][0]["servicetype"]
  lb_lbmethod = resp_obj["lbvserver"][0]["lbmethod"].downcase
  lbmethod = $node['workorder']['rfcCi']['ciAttributes']['lbmethod']

  context "configuration entries" do
    it "should exist" do
      expect(lbip).not_to be_nil
      expect(lbservicetype).to eq(servicetype)
      expect(lb_lbmethod).to eq(lbmethod)
    end
  end
end


resp_obj = JSON.parse(conn.request(
    :method=>:get,
    :path=>"/nitro/v1/config/lbvserver_servicegroup_binding/#{lb_name}").body)

exists = resp_obj["message"] =~ /Done/ ? true : false

context "lbserver_servicegroup" do
  it "should exist" do
    expect(exists).to eq(true)
  end
end

if exists
  bindings = resp_obj["lbvserver_servicegroup_binding"]
end

if !bindings.nil?
  !bindings.each do |sg|
    sg_name = sg["servicegroupname"]
    resp_obj = JSON.parse(conn.request(:method=>:get, :path=>"/nitro/v1/config/servicegroup/#{sg_name}").body)

    exists = resp_obj["message"] =~ /Done/ ? true : false
    context "servicegroup" do
      it "should exist" do
        expect(exists).to eq(true)
      end
    end

    resp_obj = JSON.parse(conn.request(:method=>:get, :path=>"/nitro/v1/config/servicegroup_servicegroupmember_binding/#{sg_name}").body)

    exists = resp_obj["message"] =~ /Done/ ? true : false
    context "servicegroup servicegroupmember binding" do
      it "should exist" do
        expect(exists).to eq(true)
      end
    end

    servicegroup_servicegroupmember_binding = ""

    if  exists
      sg_members = resp_obj["servicegroup_servicegroupmember_binding"]
      servicegroup_servicegroupmember_binding += "servicegroupmembers of: #{sg_name}\n"
      servicegroup_servicegroupmember_binding += PP.pp sg_members, ""

      $node['workorder']['payLoad']['DependsOn'].each do |dep|
        if defined?(dep['ciAttributes']['public_ip'])
          ip = dep['ciAttributes']['public_ip'].to_s

          context "compute IP" do
            it "should exist" do
              expect(servicegroup_servicegroupmember_binding).to include(ip)
            end
          end

        end

      end
    end

    resp_obj = JSON.parse(conn.request(:method=>:get,
                                       :path=>"/nitro/v1/config/servicegroup_lbmonitor_binding/#{sg_name}").body)

    exists = resp_obj["message"] =~ /Done/ ? true : false
    context "servicegroup lbmonitor binding" do
      it "should exist" do
        expect(exists).to eq(true)
      end
    end

    if exists
      sg_monitors = resp_obj["servicegroup_lbmonitor_binding"]
      sg_monitors.each do |mon|
        mon_name = mon["monitor_name"]
        resp_obj = JSON.parse(conn.request(:method=>:get, :path=>"/nitro/v1/config/lbmonitor/#{mon_name}").body)

        exists = resp_obj["message"] =~ /Done/ ? true : false
        context "lbmonitor" do
          it "should exist" do
            expect(exists).to eq(true)
          end
        end
      end
    end
  end
end


if lb_name =~ /SSL/ && lb_name !~ /BRIDGE/
  resp_obj = JSON.parse(conn.request(
      :method=>:get,
      :path=>"/nitro/v1/config/sslvserver_sslcertkey_binding/#{lb_name}").body)

  exists = resp_obj["message"] =~ /Done/ ? true : false
  context "SSL" do
    it "should exist" do
      expect(exists).to eq(true)
    end
  end

  if exists
    context "sslcertkey binding" do
      it "should exist" do
        sslvserver_sslcertkey_binding = resp_obj["sslvserver_sslcertkey_binding"]
        expect(sslvserver_sslcertkey_binding).not_to be_nil
      end
    end
  end
end