# This is the configuration file for Fezzik. See Fezzik's README for details (github.com/dmacdougall/fezzik).

set :app, "immunity_system"
set :deploy_to, "/opt/#{app}"
set :release_path, "#{deploy_to}/releases/#{Time.now.strftime("%Y%m%d%H%M")}"
set :local_path, Dir.pwd
set :user, "immunity"

common_env_vars = {
  db_user: "root",
  db_password: "",
  rack_env: "production",
  immunity_server_port: 3102,
  log_forwarder_port: 4569
}

def include_env_vars(env_vars) env_vars.each { |key, value| Fezzik.env key, value } end

Fezzik.destination :vagrant do
  set :hostname, "immunity_system_vagrant"
  set :domain, "#{user}@#{hostname}"
  include_env_vars(common_env_vars)
  Fezzik.env :log_forwarding_redis_host, hostname
  host "root@#{hostname}", :root_user
  host "#{user}@#{hostname}", :deploy_user
end

