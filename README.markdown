Immunity System
===============

Immunity is a web service which orchestrates continuous integration and deployment in stages. It's designed to
allow for fast, continuous deployment, while preventing bad code from getting into production and affecting
your customers. It's your app's immunity system.

When a new commit is made, Immunity deploys your app to one of its available regions (group of servers), runs
integration tests, and optionally monitors application metrics while receiving mirrored production traffic.

Workflow example
================

Here is a concrete example of a good Immunity workflow for a production web server called "Papi". The example
illustrates how you can configure Immunity to power your deployment pipeline.

Say that Papi is configured with four regions, each of them a single machine: Sandbox1, Sandbox2, Prod3,
Prod4. The first two are used for development and do not receive production, whereas the second two do.

"Application metrics" are collected using a monitoring system (like Hastur). They are metrics like error
rates, latency, SQL query count, memory usage, successful signups, etc. While running, Papi reports its
metrics to that metrics system, and Immunity is set up to read those metrics.

1. A new commit is made to Papi.git, which causes Immunity to deploy this version of Papi to Sandbox1.
2. Papi's integration tests are run on Sandbox1.
3. If they pass, Papi is deployed to Sandbox2.
4. Papi's integration tests are run on Sandbox2.
5. If they pass, Sandbox2 starts receiving mirrored readonly production traffic from Prod3.
6. After 5 minutes, the application metrics recorded on Sandbox2 are compared to the metrics recorded on
Prod3. If they are within an acceptable range, this version of Papi is deemed good and ready for production
traffic. In the Immunity UI, this version of Papi can now be deployed to prod3 (which does receive production
traffic) by the click of a button.
7. When that button is clicked, this new version of Papi is deployed to Prod3.
8. For each remaining server (e.g. Prod4), the server is deployed to, has its integration tests run, and app
metrics monitored, one server at a time.

In this example, Sandbox1 is used to provide the same workflow as a traditional continuous integration server.
New versions of Papi are deployed right away, tests are run, and if something fails, developers are notified.
Feedback for test breakages is quick and clear.

Sandbox2 gets deployed to less frequently, because the step of monitoring the app's metrics takes longer. This
step is more realistic and safe and is used to verify that the new version of Papi will perform well in
production. It's used to detect more subtle breakages under real customer usage and load.

Why Immunity
============

Note that Immunity is a work in progress and not yet in production use.

Building a continuous, staged deployment workflow for your app is hard and always application-specific.
Immunity makes it easier to script these workflows:

* A basic workflow engine that's specific to deploying versions of code to groups of servers, including
"monitoring application metrics".
* A UI which succinctly visualizes the current state of your deployment pipeline along with metrics useful for
troubleshooting.
* A focused and easy to extend code base.

These features reduce a lot of complexity needed for scripting a robust continuous deployment and ensure that
you don't have to beat your tool into submission to get it to do what you want.

Why not use something like Jenkins for this?
--------------------------------------------
Jenkins is a generic job server which can be used to power to run jobs like "deployment version X" or "run the
tests for version Y". However, since it is a generic job server, it takes a lot of configuration to set up a
sophisticated staged deployment, and it does not naturally support the notion of a "application monitoring
period", does not naturally visualize.

Most importantly, when depending on this deployment pipeline as the lifeline of your app or business, it's
critical to have your deployment pipeline dashboarded succinctly and to have informative and useful
troubleshooting information in the UI, which generic job servers cannot do.


Hacking on Immunity
===================

### Setup

Set your Mac up for development:

    ./script/initial_app_setup.rb

### Running

See the Procfile for the commands you can run to launch the web server, Resque, and clockwork.

To run them all together in one terminal, we use [Foreman](https://github.com/ddollar/foreman):

    bundle exec foreman start

You'll need to already have mysql and redis-server already running.

### Configuring your app in Immunity

Edit the config/immunity_apps.rb file to set up your app and its regions.

Then clone your app's repo into ~/immunity_repos, using the same directory name that you specified in
config/immunity_apps.rb. Now, Immunity will poll this repo for new commits.

Deploying Immunity
==================

Start your [Vagrant](http://vagrantup.com) VM:

    vagrant up

Prepare vagrant for Immunity:

    ./script/setup_vagrant.rb

    # You can ssh into vagrant as root now:
    ssh root@immunity_system_vagrant

Deploy the immunity system to vagrant.

    bundle exec fez vagrant deploy

# Read through the Fezzik deploy config in `config/tasks/deploy.rake`.
