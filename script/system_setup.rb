#!/usr/bin/env ruby
# This sets up the system software needed for a deploy.
# NOTE(philc): This could be ported to Puppet or Chef. I tried to write this initially with Chef and Puppet,
# but the weight of them crushed me.

# We've written this brief DSL for specifying requirements. Read through it first.
require File.expand_path(File.join(File.dirname(__FILE__), "system_setup_dsl.rb"))

def ensure_linux!
  if `uname`.downcase.include?("darwin")
    fail_and_exit "This setup script is intended for Ubuntu Linux. Don't run it on your Mac."
  end
end

ensure_linux!
include DependencyDsl

ubuntu_packages = [
  "git-core", # Required for rbenv.
  "curl", "build-essential", "libxslt1-dev", "libxml2-dev", "libssl-dev", # Required for running rubybuild.
  "g++", "dialog", # For installing native extensions.
  "mysql-client-5.1",
  "libmysqlclient-dev" # For building the native MySQL gem.
]
ubuntu_packages.each { |package| ensure_package(package) }

ensure_file("script/system_setup_files/.bashrc", "#{ENV['HOME']}/.bashrc")

dep "rbenv" do
  met? { command_exists?("rbenv") }
  meet do
    # These instructions are from https://github.com/sstephenson/rbenv/wiki/Using-rbenv-in-Production
    command = "wget -q -O - https://raw.github.com/fesplugas/rbenv-installer/master/bin/rbenv-installer | bash"
    check_status(command, true)
    # Ensure rbenv is in the PATH for the remainder of this script's execution.
    ENV["PATH"] = "#{ENV['HOME']}/.rbenv/bin:#{ENV['PATH']}"
  end
end

dep "rbenv ruby 1.9" do
  ruby_version = "1.9.2-p290"
  met? { `which ruby`.include?("rbenv") && `ruby -v`.include?(ruby_version.gsub("-", "")) }
  meet { puts `rbenv install #{ruby_version}` }
end

ensure_gem("bundler")

satisfy_dependencies()