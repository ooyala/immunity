require "simple_memoize"
require "lib/sinatra_api_helpers" # for symbolize_hash_keys.

# This represents an application that Immunity is managing.
# Columns:
# - name
# - active: if false, builds are not run from this application.
# - is_test: indicates that this is a test app used for integration testing. Builds in this app will
#   skip certain phases.
class Application < Sequel::Model
  one_to_many :regions, :order => :ordinal.asc
  add_association_dependencies :regions => :destroy

  def region_with_name(name) regions_dataset.first(:name => name) end

  # Ensures this application matches the application definition as specified by properties_hash.
  # That will include creating and destroying regions as needed, and ensuring the regions are ordered
  # to match the region ordering given in properties_hash.
  # - properties_hash looks like:
  #   { "regions": [{ name: "prod1", host: "prod1.example.com" }, ... ] }
  def update_from_properties_hash(properties_hash)
    DB.transaction do
      self.is_test = (properties_hash[:is_test] == true)
      new_regions = properties_hash[:regions]
      region_names = new_regions.map { |region| region[:name].to_s }
      self.regions.reject { |region| region_names.include?(region.name) }.each(&:destroy)

      new_regions.each.with_index do |region, index|
        db_region = Region.find_or_create(:name => region[:name], :application_id => self.id)
        db_region.host = region[:host]
        db_region.ordinal = index
        db_region.requires_manual_approval = (region[:requires_manual_approval] == true)
        db_region.requires_monitoring = (region[:requires_monitoring] == true)
        db_region.save
      end
      self.save
    end
    nil
  end

  def self.create_application_from_hash(app_name, properties_hash)
    properties_hash = SinatraApiHelpers.symbolize_hash_keys(properties_hash)
    app = Application.find_or_create(:name => app_name.to_s)
    app.update_from_properties_hash(properties_hash)
    app
  end

  # The next region in the deploy chain after the current region. Returns nil if there is no region after
  # current_region.
  def next_region(current_region) regions[regions.index(current_region) + 1] end

  def is_test?() is_test end

  memoize :region_with_name
end