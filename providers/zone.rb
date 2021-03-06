# A sha256 hash is used to determine whether any records have changed
require 'digest'
require 'date'

action :delete do
  if ::File.exists?("db.#{new_resource.zone_name}")
    file "db.#{new_resource.zone_name}" do
      action :delete
      notifies :reload, "service[#{node['bind']['service']}]", :immediately
    end

    new_resource.updated_by_last_action(true)
  else
    new_resource.updated_by_last_action(false)
  end
end

action :create do
  template "#{node['bind']['db_dir']}/db.#{new_resource.zone_name}" do
    source 'zone.db.erb'
    mode 0644
    owner 'root'
    group 'root'
    variables(zone: new_resource.zone_name,
              records: parsed_records,
              serial: new_resource.serial || serial,
              retry_time: new_resource.retry_time,
              refresh_time: new_resource.refresh_time,
              expire_time: new_resource.expire_time,
              nameservers: new_resource.nameservers,
              cache_minimum: new_resource.cache_minimum)
    notifies :restart, "service[#{node['bind']['service']}]"
  end
  new_resource.updated_by_last_action(true)
end

action :reverse do
  zone_name = new_resource.network.split('.')[0..-2].reverse.join('.') + '.IN-ADDR.ARPA'

  template "#{node['bind']['db_dir']}/db.#{zone_name}" do
    source 'zone.db.erb'
    mode 0644
    owner 'root'
    group 'root'
    variables(zone: zone_name,
              records: reversed_records,
              serial: new_resource.serial || serial(zone_name),
              retry_time: new_resource.retry_time,
              refresh_time: new_resource.refresh_time,
              expire_time: new_resource.expire_time,
              nameservers: new_resource.nameservers,
              cache_minimum: new_resource.cache_minimum)
    notifies :restart, "service[#{node['bind']['service']}]"
  end

  node.set['bind']['zones'].push(zone_name)
  new_resource.updated_by_last_action(true)
end

def serial(zone_name = new_resource.zone_name)
  new_hash = Digest.hexencode(Digest::SHA256.digest new_resource.records.to_s)
  if node['bind']['records_hash'].nil?
    node.set['bind']['records_hash'][zone_name] = new_hash
    node.set['bind']['zone_serial'][zone_name] = new_serial
  else
    if new_hash != node['bind']['records_hash'][zone_name]
      node.set['bind']['records_hash'][zone_name] = new_hash
      node.set['bind']['zone_serial'][zone_name] = new_serial
    end
  end
  node['bind']['zone_serial'][zone_name]
end

def new_serial
  DateTime.now.strftime('%Y%m%d%H')
end

def reversed_records
  records = {}
  new_resource.records.each do |name, values|
    records.merge!(
      values['ip'].split('.').last => {
        'ttl' => values['ttl'] || '',
        'class' => values['class'] || 'IN',
        'rr' => 'PTR',
        'name' => "#{name}.#{new_resource.zone_name}.",
        'priority' => ''
      }
    )
  end
  records
end

def parsed_records
  records = {}
  new_resource.records.each do |name, values|
    records.merge!(
      name => {
        'ttl' => values['ttl'] || '',
        'class' => values['class'] || 'IN',
        'rr' => values['rr'] || 'A',
        'name' => values['ip'],
        'priority' => values['priority'] || ''
      }
    )
    unless values['cnames'].nil?
      values['cnames'].each do |cname|
        records.merge!(
          cname => {
            'ttl' => values['ttl'] || '',
            'class' => values['class'] || 'IN',
            'rr' => 'CNAME',
            'priority' => '',
            'name' => name
          }
        )
      end
    end
  end
  records
end
