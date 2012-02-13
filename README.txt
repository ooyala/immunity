# Setting up for development
./script/initial_setup.rb

# Running
See the Procfile for the commands you can run to launch the web server, resque, and clockwork.

To run them all together in one terminal, we use Foreman (https://github.com/ddollar/foreman):
bundle exec foreman start

You'll need to have already have mysql and redis-server already running.

# Pulling in builds
Fetch_commits will grab commits from repos found in ~/immunity_repos, so you'll need to clone
some git repos into that directory in order to fetch builds

# Deploying Locally
You'll need to make sure that SSH is enabled on your mac (via System Preferences > Sharing > Enabling "Remote Login"), and ensure that your public key (in .ssh) is renamed to authorized_keys2
