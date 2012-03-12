# This is small goal-oriented DSL for installing system components. It's inspired by Babushka
# (https://github.com/benhoskings/babushka) and could be replaced by Babushka (or Puppet or Chef)
# when we want more features.
require "fileutils"
require "digest/md5"

# Usage:
#
# include DependencyDsl
# dep "my library" do
#   met? { (check if your dependency is met) }
#   meet { (install your dependency) }
# end
module DependencyDsl
  def dep(name)
    @dependencies ||= []
    @dependencies.push(@current_dependency = { :name => name })
    yield
  end
  def met?(&block) @current_dependency[:met?] = block end
  def meet(&block) @current_dependency[:meet] = block end
  def command_exists?(command) `which #{command}`.size > 0 end
  def fail_and_exit(message) puts message; exit 1 end

  # Runs a command and raises an exception if its exit status was nonzero.
  def check_status(command, log_output = false, log_command = false)
    puts command if log_command
    output = `#{command}`
    puts output if log_output
    raise "#{command} had a failure exit status of #{$?.to_i}" unless $?.to_i == 0
    true
  end

  def satisfy_dependencies
    @dependencies.each do |dependency|
      unless dependency[:met?].call
        puts "* Dependency #{dependency[:name]} is not met. Meeting it."
        dependency[:meet].call
        unless dependency[:met?].call
          fail_and_exit("'met?' for #{dependency[:name]} is still false after running 'meet'.")
        end
      end
    end
  end

  def package_installed?(package) `dpkg -s #{package} 2> /dev/null | grep Status`.match(/\sinstalled/) end
  def install_package(package)
    # Specify a noninteractive frontend, so dpkg won't prompt you for info. -q is quiet; -y is "answer yes".
    check_status("export DEBIAN_FRONTEND=noninteractive && apt-get install -qy #{package}", true, true)
  end

  def ensure_package(package)
    dep package do
      met? { package_installed?(package) }
      meet { install_package(package) }
    end
  end

  def ensure_gem(gem)
    dep gem do
      met? do
        command = %Q{ruby -rubygems -e 'exit !Gem::Specification.find_all_by_name("#{gem}").empty?'}
        check_status(command) rescue false
      end
      meet { check_status("gem install #{gem} --no-ri --no-rdoc", true, true) }
    end
  end

  # Ensures the file at dest_path is exactly the same as the one in source_path.
  def ensure_file(source_path, dest_path)
    dep dest_path do
      met? do
        raise "This file does not exist: #{source_path}" unless File.exists?(source_path)
        File.exists?(dest_path) && (Digest::MD5.file(source_path) == Digest::MD5.file(dest_path))
      end
      meet { FileUtils.cp(source_path, dest_path) }
    end
  end
end
