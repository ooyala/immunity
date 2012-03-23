#!/usr/bin/env ruby
# This sets up the system software on Ubuntu needed for a deploy.
# NOTE(philc): This logic could be ported to Puppet or Chef. I tried to write this initially with Chef and
# Puppet, but the weight of them almost crushed me.

# We've written this brief DSL for specifying requirements. Read through it first.
require File.expand_path(File.join(File.dirname(__FILE__), "system_setup_dsl.rb"))

include SystemSetupDsl
unless `uname`.downcase.include?("linux")
  fail_and_exit "This setup script is intended for Linux on our servers. Don't run it on your Macbook."
end

ubuntu_packages = [
  "git-core", # Required for rbenv.
  "curl", "build-essential", "libxslt1-dev", "libxml2-dev", "libssl-dev", # Required for running rubybuild.
  "g++", # For installing native extensions.
  "libmysqlclient-dev", # For building the native MySQL gem.
  "redis-server",
  "mysql-server",
  "nginx"
]
ubuntu_packages.each { |package| ensure_package(package) }

ensure_file("script/system_setup_files/.bashrc", "#{ENV['HOME']}/.bashrc")

dep "rbenv" do
  met? { in_path?("rbenv") }
  meet do
    # These instructions are from https://github.com/sstephenson/rbenv/wiki/Using-rbenv-in-Production
    shell "wget -q -O - https://raw.github.com/fesplugas/rbenv-installer/master/bin/rbenv-installer | bash"
    unless ARGV.include?("--forked-after-rbenv") # To guard against an infinite forking loop.
      exec "bash -c 'source ~/.bashrc; #{__FILE__} --forked-after-rbenv'"
    end
  end
end

dep "rbenv ruby 1.9" do
  ruby_version = "1.9.2-p290"
  met? { `which ruby`.include?("rbenv") && `ruby -v`.include?(ruby_version.gsub("-", "")) }
  meet do
    puts "Installing Ruby will take about 5 minutes."
    shell "rbenv install #{ruby_version}"
    shell "rbenv rehash"
  end
end

ensure_file("script/system_setup_files/nginx_site.conf", "/etc/nginx/sites-enabled/immunity_system.conf") do
  `/etc/init.d/nginx restart`
end

dep "configure nginx" do
  met? { !File.exists?("/etc/nginx/sites-enabled/default") }
  meet do
    # Ensure nginx gets started on system boot. It's still using non-Upstart init scripts.
    `update-rc.d nginx defaults`
    # This default site configuration is not useful.
    FileUtils.rm("/etc/nginx/sites-enabled/default")
    `/etc/init.d/nginx restart`
  end
end

ensure_gem("bundler")

# Note that this git_ssh_private_key is not checked into the repo. It gets created at deploy time.
ensure_file("script/system_setup_files/git_ssh_private_key", "#{ENV['HOME']}/.ssh/git_ssh_private_key") do
  # The ssh command requires that this file have very low privileges.
  shell "chmod 0600 #{ENV['HOME']}/.ssh/git_ssh_private_key"
end

ensure_file("script/system_setup_files/ssh_config", "#{ENV['HOME']}/.ssh/config")

satisfy_dependencies()