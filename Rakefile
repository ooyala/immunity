require "bundler/setup"
require "pathological"
require "rake/testtask"

# All resque jobs must be required here. To run resque: QUEUE=* rake resque:work (or use bin/run_resque.rb).
require "resque/tasks"
require "resque_jobs/fetch_commits"
require "resque_jobs/run_monitor"

# We use Fezzik for deployments.
require "fezzik"
Fezzik.init(:tasks => "config/tasks")
require "config/deploy_config"

namespace :test do
  Rake::TestTask.new(:integrations) do |task|
    task.libs << "test"
    task.test_files = FileList["test/integration/*"]
  end
end

task :test => "test:integrations"

