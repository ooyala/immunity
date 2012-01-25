# Setting up for development
mysqladmin5 -u root create immunity_system

# Running
See the Procfile for the commands you can run to launch the web server, resque, and clockwork.

To run them all together in one terminal, we use Foreman (https://github.com/ddollar/foreman):
bundle exec foreman start