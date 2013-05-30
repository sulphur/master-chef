if node['platform'] == "ubuntu" && node.apt.master_chef_add_apt_repo

  add_apt_repository "ppa_nginx" do
    url "http://ppa.launchpad.net/nginx/stable/ubuntu"
    key "C300EE8C"
    key_server "keyserver.ubuntu.com"
  end

end

if node.lsb.codename == "squeeze"  && node.apt.master_chef_add_apt_repo

  add_apt_repository "nginx" do
    url "http://nginx.org/packages/debian/"
    components ["nginx"]
    key "7BD9BF62"
    key_server "keyserver.ubuntu.com"
  end

  directory "/etc/nginx/sites-enabled" do
    recursive true
  end

end

package node.nginx.package_name do
  version node.nginx[:nginx_version] if node.nginx[:nginx_version]
end

[
  "/etc/nginx/sites-enabled/default",
  "/etc/nginx/sites-available/default",
  "/etc/nginx/conf.d/default.conf",
  "/etc/nginx/conf.d/example_ssl.conf"
  ].each do |f|
  file f do
    action :delete
  end
end

Chef::Config.exception_handlers << ServiceErrorHandler.new("nginx", "nginx:.*")

service "nginx" do
  supports :status => true, :restart => true, :reload => true
  action auto_compute_action
end

if node.nginx[:deploy_default_config]

  template "/etc/nginx/nginx.conf" do
    if node.nginx[:config][:worker_processes]
      nb_workers =  node.nginx[:config][:worker_processes]
    else
      nb_workers = node.cpu.total
    end
    variables :worker_processes => nb_workers
    source "nginx.conf.erb"
    mode '0644'
    notifies :reload, "service[nginx]"
  end

  directory node.nginx.default_root do
    recursive true
    owner "www-data"
  end

  if node.nginx[:locations]

    node.nginx.locations.keys.sort.each do |k|
      directory node.nginx.locations[k]["path"] do
        owner node.nginx.locations[k]["owner"]
        recursive true
      end

      link "#{node.nginx.default_root}#{k}" do
        to node.nginx.locations[k]["path"]
      end
    end

  end

end

if node.nginx.default_vhost.enabled

  nginx_vhost "nginx:default_vhost" do
    cookbook "nginx"
    options :root => node.nginx.default_root
  end

end

if node.nginx[:proxy_locations]

  node.nginx.proxy_locations.each do |k, v|

    nginx_add_default_location k do
      upstream v[:upstram]
      content v[:content]
    end

  end

end

delayed_exec "Remove useless nginx vhost" do
  after_block_notifies :restart, resources(:service => "nginx")
  block do
    updated = false
    vhosts = find_resources_by_name_pattern(/^\/etc\/nginx\/sites-enabled\/.*\.conf$/).map{|r| r.name}
    Dir["/etc/nginx/sites-enabled/*.conf"].each do |n|
      unless vhosts.include? n
        Chef::Log.info "Removing vhost #{n}"
        File.unlink n
        updated = true
      end
    end
    updated
  end
end
