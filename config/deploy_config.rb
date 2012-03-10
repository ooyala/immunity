# This is the configuration file for fezzik.
# Define variables here as you would for Vlad the Deployer.
# A full list of variables can be found here:
#     http://hitsquad.rubyforge.org/vlad/doco/variables_txt.html

set :app, "immunity_system"
set :deploy_to, "/opt/ooyala/#{app}"
set :release_path, "#{deploy_to}/releases/#{Time.now.strftime("%Y%m%d%H%M")}"
set :local_path, Dir.pwd
set :user, "root"

# Each destination is a set of machines and configurations to deploy to.
# You can deploy to a destination from the command line with:
#     fez to_dev deploy
#
# :domain can be an array if you are deploying to multiple hosts.
#
# You can set environment variables that will be loaded at runtime on the server
# like this:
#     Fezzik.env :rack_env, "production"
# This will also generate a file on the server named config/environment.rb, which you can include
# in your code to load these variables as Ruby constants. You can create your own config/environment.rb
# file to use for development, and it will be overwritten at runtime.

# This localhost target is for testing the deployment pipeline with quick turnaround times.
#

Fezzik.destination :vagrant do
  set :domain, "immunity_system_vagrant"
  Fezzik.env :immunity_server_port, 3102
  Fezzik.env :rack_env, "production"
  Fezzik.env :db_location, "DBI:Mysql:vstreams"
  Fezzik.env :db_user, "root"
  Fezzik.env :db_password, ""
  Fezzik.env :num_workers, 2
  Fezzik.env :unicorn_pid_file, "#{deploy_to}/unicorn.pid"
  Fezzik.env :helios_root, "#{current_path}"
  Fezzik.env :sphinx_server, "localhost"
  Fezzik.env :sphinx_port, 3312
  Fezzik.env :sphinx_rt_server, "127.0.0.1"
  Fezzik.env :sphinx_rt_mysql_port, 9306
end
