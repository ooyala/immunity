#!/usr/bin/env ruby-local-exec
# A quick environment setup script to help developers get started quickly.
# This will:
# - check out repos the immunity system needs
# - create mysql tables & run migrations
# 
# Usage:
#   initial_app_setup.rb [envrionment=development]
#
# The "development" environment adds a few extras +not+++++ needed in production.

environment = ARGV[0] || "development"

require File.expand_path(File.join(File.dirname(__FILE__), "system_setup_dsl.rb"))

include SystemSetupDsl

def db_exists?(db_name)
  shell("#{mysql_command} -u root #{db_name} -e 'select 1' 2> /dev/null", :log => false) rescue false
end

def mysql_command() @mysql_command ||= (`which mysql || which mysql5`).chomp end
def mysqladmin_command() @mysql_admin ||= (`which mysqladmin || which mysqladmin5`).chomp end

dep "create mysql immunity_system database" do
  met? { db_exists?("immunity_system") }
  meet { shell "#{mysqladmin_command} -u root create immunity_system" }
end

dep "bundle install" do
  met? { shell("bundle check", :log => false) rescue false }
  meet do
    # NOTE(philc): We *are* installing the test group because currently we run integration tests on the
    # prod boxes.
    args = (environment == "production") ? "--without dev" : ""
    shell "bundle install --quiet #{args}"
  end
end

dep "migrations" do
  has_run_once = false
  met? do
    result = has_run_once
    has_run_once = true
    result
  end

  meet { shell "script/run_migrations.rb" }
end

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
