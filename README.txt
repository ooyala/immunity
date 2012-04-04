# Setting up for development
./script/initial_app_setup.rb

# Running
See the Procfile for the commands you can run to launch the web server, resque, and clockwork.

To run them all together in one terminal, we use Foreman (https://github.com/ddollar/foreman):
bundle exec foreman start

You'll need to already have mysql and redis-server already running.

# Pulling in builds
Fetch_commits will grab commits from repos found in ~/immunity_repos, so you'll need to clone
some git repos into that directory in order to fetch builds.

Testing the Immunity System's deploy using Vagrant
--------------------------------------------------
# Read about how Vagrant works: http://vagrantup.com. Then start the VM:
vagrant up

# Setup vagrant (enable root login via ssh, etc.):
./script/setup_vagrant.rb

# You can ssh into vagrant as root now:
ssh root@immunity_system_vagrant

# Deploy the immunity system to vagrant.
bundle exec fez vagrant deploy

# Read about Fezzik and read over config/tasks/deploy.rake.