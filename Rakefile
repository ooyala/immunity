require "bundler/setup"
require "pathological"
require "rake/testtask"
require "resque/tasks"
require "resque_jobs/fetch_commits"
require "resque_jobs/run_monitor"

namespace :test do
  Rake::TestTask.new(:integrations) do |task|
    task.libs << "test"
    task.test_files = FileList["test/integration/*"]
  end

end

task :test => "test:integrations"
