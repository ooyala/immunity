# This is small goal-oriented DSL for installing system components, similar in purpose to Chef and Puppet.
# It's inspired by Babushka (http://github.com/benhoskings/babushka) but is simpler and is tailored for
# provisioning a production webapp.
#
# Usage:
#
# require "system_setup_dsl"
# include SystemSetupDsl
# dep "my library" do
#   met? { (check if your dependency is met) }
#   meet { (install your dependency) }
# end

require "fileutils"
require "digest/md5"

module SystemSetupDsl
  def dep(name)
    @dependencies ||= []
    @dependencies.push(@current_dependency = { :name => name })
    yield
  end
  def met?(&block) @current_dependency[:met?] = block end
  def meet(&block) @current_dependency[:meet] = block end
  def in_path?(command) `which #{command}`.size > 0 end
  def fail_and_exit(message) puts message; exit 1 end

  # Runs a command and raises an exception if its exit status was nonzero.
  # - log_output: true by default
  # - log_command: true by default
  # - check_exit_code: raises an error if the command had a non-zero exit code. True by default.
  def shell(command, options = {})
    puts command unless options[:log_command] == false
    output = `#{command}`
    puts output unless output.empty? || options[:log_output] == false
    raise "#{command} had a failure exit status of #{$?.to_i}" unless $?.to_i == 0
    true
  end

  def satisfy_dependencies
    STDOUT.sync = true # Ensure that we flush logging output as we go along.
    @dependencies.each do |dep|
      unless dep[:met?].call
        puts "* Dependency #{dep[:name]} is not met. Meeting it."
        dep[:meet].call
        fail_and_exit %Q("met?" for #{dep[:name]} is still false after running "meet".) unless dep[:met?].call
      end
    end
  end

  def package_installed?(package) `dpkg -s #{package} 2> /dev/null | grep Status`.match(/\sinstalled/) end
  def install_package(package)
    # Specify a noninteractive frontend, so dpkg won't prompt you for info. -q is quiet; -y is "answer yes".
    shell "export DEBIAN_FRONTEND=noninteractive && apt-get install -qy #{package}"
  end

  def ensure_package(package)
    dep package do
      met? { package_installed?(package) }
      meet { install_package(package) }
    end
  end

  def gem_installed?(gem)
    shell %Q{ruby -rubygems -e 'exit !Gem::Specification.find_all_by_name("#{gem}").empty?'} rescue false
  end

  def ensure_gem(gem)
    dep gem do
      met? { gem_installed?(gem) }
      meet { shell "gem install #{gem} --no-ri --no-rdoc" }
    end
  end

  # Ensures the file at dest_path is exactly the same as the one in source_path.
  # Invokes the given block if the file is changed. Use this block to restart a service, for instance.
  def ensure_file(source_path, dest_path, &on_change)
    dep dest_path do
      met? do
        raise "This file does not exist: #{source_path}" unless File.exists?(source_path)
        File.exists?(dest_path) && (Digest::MD5.file(source_path) == Digest::MD5.file(dest_path))
      end
      meet do
        FileUtils.cp(source_path, dest_path)
        on_change.call if on_change
      end
    end
  end
end
