require 'resolv'
require 'ipaddr'
require 'excon'

is_windows = ENV['OS'] == 'Windows_NT'

begin
  CIRCUIT_PATH = '/opt/oneops/inductor/circuit-oneops-1'
  COOKBOOKS_PATH = "#{CIRCUIT_PATH}/components/cookbooks".freeze
  require "#{CIRCUIT_PATH}/components/spec_helper.rb"
  require "#{COOKBOOKS_PATH}/fqdn/test/integration/library.rb"
rescue Exception =>e
  CIRCUIT_PATH = "#{is_windows ? 'C:/Cygwin64' : ''}/home/oneops"
  require "#{CIRCUIT_PATH}/circuit-oneops-1/components/spec_helper.rb"
  require "/home/oneops/circuit-oneops-1/components/cookbooks/fqdn/test/integration/library.rb"
end

lib = Library.new

cloud_name = $node['workorder']['cloud']['ciName']
service_attrs = lib.get_dns_service

customer_domain = lib.get_customer_domain

entries = Array.new

is_hostname_entry = false

describe "DependsOn entry" do
  context "DependsOn entry" do
    it "should exist" do
      expect($node['workorder']['payLoad']['DependsOn']).not_to be_nil
    end
  end
end


lbs = $node['workorder']['payLoad']['DependsOn'].select { |d| d['ciClassName'] =~ /Lb/ }
os = $node['workorder']['payLoad']['DependsOn'].select { |d| d['ciClassName'] =~ /Os/ }
cluster = $node['workorder']['payLoad']['DependsOn'].select { |d| d['ciClassName'] =~ /Cluster/ }

ad_ci = nil
if lib.is_windows && os.size == 1
  ad_ci = os
  ad_object_name = 'hostname'
elsif lib.is_windows && cluster.size == 1
  ad_ci = cluster
  ad_object_name = 'cluster_name'
end

if ad_ci
  dns_name = (ad_ci[0]['ciAttributes'][ad_object_name] + '.' + lib.get_windows_domain).downcase
  is_hostname_entry = true if os.size == 1

elsif $node['workorder']['payLoad'].has_key?("Entrypoint")
  ci = $node['workorder']['payLoad']['Entrypoint'][0]
  dns_name = (ci['ciName'] +customer_domain).downcase

elsif lbs.size > 0
  ci = lbs.first
  ci_name_parts = ci['ciName'].split('-')
  ci_name_parts.pop
  ci_name_parts.pop
  ci_name = ci_name_parts.join('-')
  dns_name = (ci_name + customer_domain).downcase

else

  if os.size == 0

    ci_name = $node['workorder']['payLoad']['RealizedAs'].first['ciName']
    dns_name = (ci_name + "." + $node['workorder']['box']['ciName'] + customer_domain).downcase

  else

    context "multiple os for same fqdn" do
      it "should not exist" do
        exists = (os.size > 1)
        expect(exists).to eq(false)
      end
    end


    is_hostname_entry = true
    ci = os.first

    provider_service = $node['workorder']['services']['dns'][cloud_name]['ciClassName'].split(".").last.downcase
    if provider_service =~ /azuredns/
      dns_name = (ci['ciAttributes']['hostname']).downcase
    else
      dns_name = (ci['ciAttributes']['hostname'] + customer_domain).downcase
    end
  end
end


aliases = Array.new
if $node['workorder']['rfcCi']['ciAttributes'].has_key?("aliases") && !is_hostname_entry
  begin
    aliases = JSON.parse($node['workorder']['rfcCi']['ciAttributes']['aliases'])
  rescue Exception =>e
    puts "could not parse aliases json"
  end
end


full_aliases = Array.new
if $node['workorder']['rfcCi']['ciAttributes'].has_key?("full_aliases") && !is_hostname_entry
  begin
    full_aliases = JSON.parse($node['workorder']['rfcCi']['ciAttributes']['full_aliases'])
  rescue Exception =>e
    puts "could not parse full_aliases json"
  end
end




context "cloud_dns_id" do
  it "should exist" do
    exists = service_attrs['cloud_dns_id'].nil? || service_attrs['cloud_dns_id'].empty?
    expect(exists).to eq(false)
  end
end

deps = $node['workorder']['payLoad']['DependsOn'].select { |d| d['ciAttributes'].has_key? "dns_record" }
values = lib.get_dns_values(deps)

entries.push({:name => dns_name, :values => values })
deletable_entries = [{:name => dns_name, :values => values }]

values.each do |ip|
  context "FQDN mapping to IP" do
    it "should exist" do
      command_execute = "host "+dns_name
      result = `#{command_execute}`
      expect(result).to include(ip)
    end
  end
end

aliases.each do |a|
  next if a.empty?
  next if a == $node['workorder']['box']['ciName']
  alias_name = a + customer_domain
  entries.push({:name => alias_name, :values => dns_name })
  deletable_entries.push({:name => alias_name, :values => dns_name })

  context "aliases" do
    it "should exist" do
      command_execute = "host "+alias_name
      result = `#{command_execute}`
      expect(result).to include(dns_name)
    end
  end

end

if ad_ci
  primary_platform_dns_name = dns_name.split('.').first + get_customer_domain.split('.').select{|i| (i != service_attrs['cloud_dns_id'])}.join('.')
else
  primary_platform_dns_name = dns_name.split('.').select{|i| (i != service_attrs['cloud_dns_id'])}.join('.')
end

if $node['workorder']['rfcCi']['ciAttributes'].has_key?("ptr_enabled") &&
    $node['workorder']['rfcCi']['ciAttributes']['ptr_enabled'] == "true"

  ptr_value = dns_name
  if $node['workorder']['rfcCi']['ciAttributes']['ptr_source'] == "platform"
    ptr_value = primary_platform_dns_name
    if is_hostname_entry
      ptr_value = $node['workorder']['box']['ciName']
      ptr_value += customer_domain.gsub("\."+service_attrs['cloud_dns_id']+"\."+service_attrs['zone'],"."+service_attrs['zone'])
    end
  end

  values.each do |ip|
    next unless ip =~ /^\d+\.\d+\.\d+\.\d+$/ || ip =~ Resolv::IPv6::Regex
    ptr = {:name => ip, :values => ptr_value.downcase}
    entries.push(ptr)
    deletable_entries.push(ptr)

    context "PTR entry" do
      it "should exist" do
        command_execute = "host "+ip
        result = `#{command_execute}`
        ptr_val = ptr_value.downcase
        expect(result).to include(ptr_val)
      end
    end
  end
end


if $node.has_key?("gslb_domain") && !$node['gslb_domain'].nil?
  value_array = [ $node['gslb_domain'] ]
else
  value_array = []
  if values.class.to_s == "String"
    value_array.push(values)
  else
    value_array += values
  end

end

is_a_record = false
value_array.each do |val|
  if val =~ /^\d+\.\d+\.\d+\.\d+$/ || val =~ Resolv::IPv6::Regex
    is_a_record = true
  end
end

if $node['workorder']['cloud']['ciAttributes']['priority'] != "1"
  if !$node.has_key?("gslb_domain")
    entries.push({:name => primary_platform_dns_name, :values => [] })

    value_array.each do |val|
      context "GSLB on secondory cloud" do
        it "should exist" do
          command_execute = "host "+primary_platform_dns_name
          result = `#{command_execute}`
          expect(result).not_to include(val)
        end
      end
    end

  end
else
  if $node['dns_action'] != "delete" ||
      ($node['dns_action']  == "delete" && $node['is_last_active_cloud']) ||
      ($node['dns_action']  == "delete" && is_a_record)

    entries.push({:name => primary_platform_dns_name, :values => value_array })
    deletable_entries.push({:name => primary_platform_dns_name, :values => value_array })

    value_array.each do |val|
      context "GSLB on primary cloud" do
        it "should exist" do
          command_execute = "host "+primary_platform_dns_name
          result = `#{command_execute}`
          expect(result).to include(val)
        end
      end
    end

  end


  aliases.each do |a|
    next if a.empty?
    next if $node['dns_action'] == "delete" && !$node['is_last_active_cloud']
    # skip if user has a short alias same as platform name
    next if a == $node['workorder']['box']['ciName']

    alias_name = a  + customer_domain
    alias_platform_dns_name = alias_name.gsub("\."+service_attrs['cloud_dns_id']+"\."+service_attrs['zone'],"."+service_attrs['zone']).downcase

    if $node.has_key?("gslb_domain") && !$node['gslb_domain'].nil?
      primary_platform_dns_name = $node['gslb_domain']
    end

    entries.push({:name => alias_platform_dns_name, :values => primary_platform_dns_name })
    deletable_entries.push({:name => alias_platform_dns_name, :values => primary_platform_dns_name })

    context "alias_platform_dns_name mapping" do
      it "should exist" do
        command_execute = "host "+alias_platform_dns_name
        result = `#{command_execute}`
        expect(result).to include(primary_platform_dns_name)
      end
    end
  end

  if !full_aliases.nil?
    full_aliases.each do |full|
      next if $node['dns_action'] == "delete" && !$node['is_last_active_cloud']

      has_wildcard = $node['workorder']['rfcCi']['ciAttributes']['full_aliases'] =~ /\*/
      full_value = primary_platform_dns_name
      if $node.has_key?("gslb_domain") && !$node['gslb_domain'].nil?
        full_value = $node['gslb_domain']
      end

      entries.push({:name => full, :values => full_value, :is_hijackable => $node['workorder']['rfcCi']['ciAttributes']['hijackable_full_aliases'] })
      deletable_entries.push({:name => full, :values => full_value})

      context "full CNAME" do
        it "should exist" do
          command_execute = "host "+full
          result = `#{command_execute}`
          expect(result).to include(full_value)
        end
      end

      describe "wildcard entry in FQDN" do
        it "entry should be enabled" do
          is_wildcard_enabled = lib.is_wildcard_enabled
          expect(is_wildcard_enabled).to eq(true)
        end
      end if has_wildcard

    end
  end

end

cloud_name = $node['workorder']['cloud']['ciName']

priority = $node['workorder']['cloud']['ciAttributes']['priority']

metadata = $node['workorder']['payLoad']['RequiresComputes'][0]['ciBaseAttributes']['metadata'].nil? ?  $node['workorder']['payLoad']['RequiresComputes'][0]['ciAttributes']['metadata'] :  $node['workorder']['payLoad']['RequiresComputes'][0]['ciBaseAttributes']['metadata']
metadata_obj= JSON.parse(metadata)
org = metadata_obj['organization']
assembly = metadata_obj['assembly']
platform = metadata_obj['platform']
env = metadata_obj['environment']
domain = defined?($node['workorder']['payLoad']['remotedns'][0]['ciAttributes']['zone']) ? $node['workorder']['payLoad']['remotedns'][0]['ciAttributes']['zone'] :  $node['workorder']['services']['dns'][cloud_name]['ciAttributes']['zone']

is_azure = cloud_name =~ /azure/ ? true : false

fqdn = (platform+"."+env+"."+assembly+"."+org+"."+domain).downcase
command_execute = "host "+fqdn

describe "FQDN on azure" do
  if is_azure
    cloud = cloud_name.split("-")[1]

    if $node['workorder']['payLoad'].has_key?("lb")

      context "FQDN mapping with LB" do
        it "should exist" do
          if $node['workorder']['services'].has_key?("gdns") && $node['workorder']['services']['gdns'].has_key?(cloud_name)
            $node['workorder']['payLoad']['lb'].each do |service|
              ip = service['ciAttributes']['dns_record']
              if  priority == '1' && service['ciAttributes']['vnames'] =~ /#{cloud}/
                entries = `#{command_execute}`
                expect(entries).to include(ip) unless ip.nil?
              end
            end
          end
        end
      end


      context "FQDN not mapping with LB" do
        it "should not exist" do
          if $node['workorder']['services'].has_key?("gdns") && $node['workorder']['services']['gdns'].has_key?(cloud_name)
            $node['workorder']['payLoad']['lb'].each do |service|
              ip = service['ciAttributes']['dns_record']
              if  priority == '2' && service['ciAttributes']['vnames'] =~ /#{cloud}/
                entries = `#{command_execute}`
                expect(entries).not_to include(ip) unless ip.nil?
              end
            end
          end
        end
      end
    end

  end
end


depends_on_lb = false
$node['workorder']['payLoad']['DependsOn'].each do |dep|
  depends_on_lb = true if dep['ciClassName'] =~ /Lb/
end

env = $node['workorder']['payLoad']['Environment'][0]['ciAttributes']

gdns_service = nil
if $node['workorder']['services'].has_key?('gdns') &&
    $node['workorder']['services']['gdns'].has_key?(cloud_name)
  gdns_service = $node['workorder']['services']['gdns'][cloud_name]
end

if env.has_key?("global_dns") && env["global_dns"] == "true" && depends_on_lb &&
    !gdns_service.nil? && gdns_service["ciAttributes"]["gslb_authoritative_servers"] != '[]'

  cloud_service= nil
  cloud_name = $node['workorder']['cloud']['ciName']
  if $node['workorder']['services'].has_key?('lb')
    cloud_service = $node['workorder']['services']['lb'][cloud_name]['ciAttributes']
  else
    cloud_service = $node['workorder']['services']['gdns'][cloud_name]['ciAttributes']
  end


  host = $node['workorder']['services']['gdns'][cloud_name]['ciAttributes']['host']
  ci = $node['workorder']['box']
  gslb_service_name = lib.get_gslb_service_name
  conn = lib.gen_conn(cloud_service,host)

  resp_obj = JSON.parse(conn.request(
      :method => :get,
      :path => "/nitro/v1/config/gslbservice/#{gslb_service_name}").body)

  if resp_obj["message"] =~ /The GSLB service does not exist/

    gslb_service_name = lib.get_gslb_service_name_by_platform

    resp_obj = JSON.parse(conn.request(
        :method=>:get,
        :path=>"/nitro/v1/config/gslbservice/#{gslb_service_name}").body)

  end

  if $node['workorder']['cloud']['ciAttributes']['priority'] == "1"
    context "GSLB service" do
      it "should exist" do
        status = resp_obj["message"]
        expect(status).to eq("Done")
      end
    end
  elsif $node['workorder']['cloud']['ciAttributes']['priority'] == "2"
    context "GSLB service name" do
      it "should not exist" do
        status = resp_obj["message"]
        expect(status).to eq("The GSLB service does not exist")
      end
    end
  end

end