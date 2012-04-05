# See vagrantup.com for complete documentation on what can go in this file.

Vagrant::Config.run do |config|

  config.vm.box = "lucid32"

  # Forward a port from the guest to the host, which allows for outside computers to access the VM. You can
  # access the immunity server running inside of Vagrant on port 6102.
  config.vm.forward_port 3102, 6102

  # Have Vagrant use your OSX VPN when it's active. Found via https://gist.github.com/1277049.
  config.vm.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]

  # Have ssh be accessible through port 2240. Hard coding this so we don't collide with other vagrant vms.
  config.vm.forward_port 22, 2240
  config.ssh.port = 2240
end
