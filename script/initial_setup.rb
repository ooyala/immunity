#!/usr/bin/env ruby-local-exec
# A quick developer/macbook environment setup script to help developers get started quickly.
# This will:
# - check out repos the immunity system needs
# - bundle install
# - create mysql tables & run migrations

def setup
  repos_path = File.expand_path("~/immunity_repos")
  repo_name = "html5player"

  run_command("bundle install")
  run_command("mkdir '#{repos_path}'") unless File.exists?(repos_path)

  # This should be done by the app, not this setup script.
  unless File.exists?(File.join(repos_path, repo_name))
    run_command("cd '#{repos_path}' && git clone ssh://git.corp.ooyala.com/#{repo_name}.git")
  end

  run_command("mysqladmin5 -u root create immunity_system") unless db_exists?("immunity_system")
  run_command("script/run_migrations.rb")
end

def db_exists?(db_name)
  `mysql5 -u root #{db_name} -e 'select 1'`
  $?.success?
end

# Runs the given command and raises an exception if its status code is nonzero.
# Returns the stdout of the command.
def run_command(command)
  require "open3"
  puts command
  stdout, stderr, status = Open3.capture3(command)
  Open3.popen3(command) { |stdin, stdout, stderr| stdout_stream = stdout }
  raise %Q(The command "#{command}" failed: #{stderr}) unless status == 0
  stdout
end

setup()