#!/usr/bin/env ruby-local-exec
# A quick environment setup script to help developers get started quickly.
# This will:
# - check out repos the immunity system needs
# - create mysql tables & run migrations
# 
# Usage:
#   initial_app_setup.rb [envrionment=development]
#
# The "development" environment adds a few extras not needed in production.

environment = ARGV[0] || "development"

`bundle check > /dev/null`
unless $?.to_i == 0
  puts "running `bundle install` (this may take a minute)"
  args = (environment == "production") ? "--without dev" : ""
  output = `bundle install #{args}`
  unless $?.to_i == 0
    puts "`bundle install` failed:"
    puts output
  end
end

require "bundler/setup"
require "terraform/dsl"
include Terraform::Dsl

ensure_run_once("git submodule init") { shell "git submodule init" }
ensure_run_once("git submodule update") { shell "git submodule update" }

def db_exists?(db_name)
  shell("#{mysql_command} -u root #{db_name} -e 'select 1' 2> /dev/null", :silent => true) rescue false
end

def mysql_command() @mysql_command ||= (`which mysql || which mysql5`).chomp end
def mysqladmin_command() @mysql_admin ||= (`which mysqladmin || which mysqladmin5`).chomp end

dep "create mysql immunity_system database" do
  met? { db_exists?("immunity_system") }
  meet { shell "#{mysqladmin_command} -u root create immunity_system" }
end

ensure_run_once("migrations") { shell "script/run_migrations.rb" }

repos_path = File.expand_path("~/immunity_repos")
FileUtils.mkdir_p(repos_path)

satisfy_dependencies()
