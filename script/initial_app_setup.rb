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

# TODO(philc): Which repos to clone shouldn't be here as part of the deploy script, but rather a piece of
# the app's configuration or settings.
repos = ["html5player"]
repos_path = File.expand_path("~/immunity_repos")
repos.each do |repo_name|
  dep "clone the #{repo_name} git repo" do
    met? { File.exists?(File.join(repos_path, repo_name)) }
    meet do
      FileUtils.mkdir_p(repos_path)
      shell "cd '#{repos_path}' && git clone ssh://git.corp.ooyala.com/#{repo_name}.git"
    end
  end
end

satisfy_dependencies()
