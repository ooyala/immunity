# See vagrantup.com for complete documentation on what can go in this file.

Vagrant::Config.run do |config|

  config.vm.box = "base"

  # Forward a port from the guest to the host, which allows for outside
  # computers to access the VM, whereas host only networking does not.
  config.vm.forward_port 3102, 3102
end
