class Library
  def get_dns_service
    cloud_name = $node['workorder']['cloud']['ciName']
    service_attrs = $node['workorder']['services']['dns'][cloud_name]['ciAttributes']

    zone_services = []
    $node['workorder']['services']['dns'].each do |s|

      if s.first =~ /#{cloud_name}\// && s.last['ciAttributes'].has_key?('criteria_type')

        if s.last['ciAttributes']['criteria_type'] == 'platform' && get_ostype == s.last['ciAttributes']['criteria_value']
          zone_services.push(s.last)
        end
      end
    end

    if zone_services.uniq.size == 1
      service_attrs = zone_services.first['ciAttributes']
    end

    return service_attrs
  end

  def get_customer_domain
    if is_windows
      arr = [$node['workorder']['payLoad']['Environment'][0]['ciName'], $node['workorder']['payLoad']['Assembly'][0]['ciName'], get_dns_service['cloud_dns_id'], get_windows_domain]
      customer_domain = '.' + arr.join('.').downcase
    else
      customer_domain = $node['customer_domain'].downcase
    end

    if customer_domain !~ /^\./
      customer_domain = '.' + customer_domain
    end

    return customer_domain
  end

  def is_windows
    return ( get_ostype == 'windows' && get_windows_domain_service )
  end

  def get_ostype

    ostype = 'linux'
    os = $node['workorder']['payLoad']['DependsOn'].select {|d| (d['ciClassName'].split('.').last == 'Os')}
    if $node['workorder']['payLoad'].has_key?('os_payload') && $node['workorder']['payLoad']['os_payload'].first['ciAttributes']['ostype'] =~ /windows/
      ostype = 'windows'
    elsif !os.empty? && os.first['ciAttributes']['ostype'] =~ /windows/
      ostype = 'windows'
    end

    return ostype
  end

  def get_windows_domain
    if get_dns_service['zone'].split('.').last(2) == get_windows_domain_service['ciAttributes']['domain'].split('.').last(2)
      return get_windows_domain_service['ciAttributes']['domain'].downcase
    else
      return get_dns_service['zone'].downcase
    end
  end

  def get_windows_domain_service
    cloud_name = $node['workorder']['cloud']['ciName']
    windows_domain = nil
    if $node['workorder']['payLoad'].has_key?('windowsdomain')
      windows_domain = $node['workorder']['payLoad']['windowsdomain'].first
    elsif $node['workorder']['services'].has_key?('windows-domain')
      windows_domain = $node['workorder']['services']['windows-domain'][cloud_name]
    end

    return windows_domain
  end


  def get_dns_values(components)
    values = Array.new
    components.each do |component|

      attrs = component['ciAttributes']

      dns_record = attrs['dns_record'] || ''

      if dns_record.empty?
        case component['ciClassName']
          when /Compute/
            if attrs.has_key?("public_dns") && !attrs['public_dns'].empty?
              dns_record = attrs['public_dns']+'.'
            else
              dns_record = attrs['public_ip']
            end

            if location == ".int" || dns_entry == nil || dns_entry.empty?
              dns_record = attrs['private_ip']
            end

          when /Lb/
            dns_record = attrs['dns_record']
          when /Cluster/
            dns_record = attrs['shared_ip']
        end
      else
        # dns_record must be all lowercase
        dns_record.downcase!
        # unless ends w/ . or is an ip address
        dns_record += '.' unless dns_record =~ /,|\.$|^\d+\.\d+\.\d+\.\d+$/ || dns_record =~ Resolv::IPv6::Regex
      end



      if dns_record =~ /,/
        values.concat dns_record.split(",")
      else
        values.push(dns_record)
      end
    end
    return values
  end

  def gen_conn(cloud_service,host)
    encoded = Base64.encode64("#{cloud_service['username']}:#{cloud_service['password']}").gsub("\n","")
    conn = Excon.new(
        'https://'+host,
        :headers => {
            'Authorization' => "Basic #{encoded}",
            'Content-Type' => 'application/x-www-form-urlencoded'
        },
        :ssl_verify_peer => false)
    return conn
  end

  def get_gslb_service_name
    env_name = $node['workorder']['payLoad']['Environment'][0]['ciName']
    platform_name = $node['workorder']['box']['ciName']
    cloud_name = $node['workorder']['cloud']['ciName']
    ci = $node['workorder']['payLoad']['DependsOn'][0]
    asmb_name = $node['workorder']['payLoad']['Assembly'][0]['ciName']
    gdns_cloud_service = $node['workorder']['services']["gdns"][cloud_name]
    dc_name = gdns_cloud_service['ciAttributes']['gslb_site_dns_id']

    return [env_name, platform_name, asmb_name, dc_name, ci["ciId"].to_s, "gslbsrvc"].join("-")
  end

  def get_gslb_service_name_by_platform
    env_name = $node['workorder']['payLoad']['Environment'][0]['ciName']
    platform_name = $node['workorder']['box']['ciName']
    cloud_name = $node['workorder']['cloud']['ciName']
    ci = $node['workorder']['box']
    asmb_name = $node['workorder']['payLoad']['Assembly'][0]['ciName']
    gdns_cloud_service = $node['workorder']['services']['gdns'][cloud_name]
    dc_name = gdns_cloud_service['ciAttributes']['gslb_site_dns_id']

    return [env_name, platform_name, asmb_name, dc_name, ci["ciId"].to_s, "gslbsrvc"].join("-")
  end

  def is_wildcard_enabled
    if $node['workorder'].has_key?('config') && !$node['workorder']['config'].empty?
      config = $node['workorder']['config']
      if config.has_key?('is_wildcard_enabled') && !config['is_wildcard_enabled'].empty? && config['is_wildcard_enabled'] == 'true'
        return true
      else
        return false
      end
    end
    return false
  end

end