require "fileutils"

namespace :fezzik do
  desc "stages the project for deployment in /tmp"
  task :stage do
    puts "staging project in /tmp/#{app}"
    FileUtils.rm_rf "/tmp/#{app}"
    FileUtils.mkdir_p "/tmp/#{app}/staged"
    # Use rsync to preserve executability and follow symlinks.
    system("rsync -aqE #{local_path}/. /tmp/#{app}/staged")
  end

  desc "performs any necessary setup on the destination servers prior to deployment"
  remote_task :setup do
    puts "setting up servers"
    run "mkdir -p #{deploy_to}/releases"
  end

  desc "after the app code has been rsynced, sets up the app's dependencies, like gems"
  remote_task :setup_app do
    puts "Setting up server dependencies. This will take 8 minutes to install Ruby the first time it's run."
    # This PATH addition is required for Vagrant, which has Ruby installed, but it's not in the default PATH.
    run "cd #{release_path} && PATH=$PATH:/opt/ruby/bin script/system_setup.rb"
    run "cd #{release_path} && bundle install --without dev --without test"
  end

  desc "rsyncs the project from its staging location to each destination server"
  remote_task :push => [:stage, :setup] do
    puts "pushing to #{target_host}:#{release_path}"
    # Copy on top of previous release to optimize rsync
    rsync "-q", "--copy-dest=#{current_path}", "/tmp/#{app}/staged/", "#{target_host}:#{release_path}"
  end

  desc "symlinks the latest deployment to /deploy_path/project/current"
  remote_task :symlink do
    puts "symlinking current to #{release_path}"
    run "cd #{deploy_to} && ln -fns #{release_path} current"
  end

  desc "runs the executable in project/bin"
  remote_task :start do
    puts "starting from #{Fezzik::Util.capture_output { run "readlink #{current_path}" }}"
    run "cd #{current_path} && (source environment.sh || true) && ./bin/run_server.sh"
  end

  desc "kills the application by searching for the specified process name"
  remote_task :stop do
    # Replace YOUR_APP_NAME with whatever is run from your bin/run_app.sh file.
    # If you'd like to do this nicer you can save the PID of your process with `echo $! > app.pid`
    # in the start task and read the PID to kill here in the stop task.
    # puts "stopping app"
    # run "(kill -9 `ps aux | grep 'YOUR_APP_NAME' | grep -v grep | awk '{print $2}'` || true)"
  end

  desc "restarts the application"
  remote_task :restart do
    Rake::Task["fezzik:stop"].invoke
    Rake::Task["fezzik:start"].invoke
  end

  desc "full deployment pipeline"
  task :deploy do
    Rake::Task["fezzik:push"].invoke
    Rake::Task["fezzik:symlink"].invoke
    Rake::Task["fezzik:setup_app"].invoke
    Rake::Task["fezzik:restart"].invoke
    puts "#{app} deployed!"
  end
end
