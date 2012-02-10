require "simple_memoize"

# This represents a deployable region (sandbox1, sandbox2) and all builds associated with that region.
# Currently this model isn't a database table.
class Region
  attr_accessor :name
  @@region_names = ["sandbox1", "sandbox2", "prod3"]
  def self.region_names() @@region_names end

  def initialize(name)
    self.name = name
  end

  def current_build
    Build.reverse_order(:id).filter("state <> 'awaiting_deploy'").first(:current_region => self.name)
  end

  def next_build
    Build.order(:id.desc).first(:current_region => self.name, :state => "awaiting_deploy")
  end

  def build_history
    BuildStatus.order(:id.desc).filter(:region => self.name).limit(10).all
  end

  memoize :next_build, :current_build, :build_history
end