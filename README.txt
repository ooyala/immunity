# Setting up for development
./script/initial_setup.rb

# Running
See the Procfile for the commands you can run to launch the web server, resque, and clockwork.

To run them all together in one terminal, we use Foreman (https://github.com/ddollar/foreman):
bundle exec foreman start

You'll need to have already have mysql and redis-server already running.