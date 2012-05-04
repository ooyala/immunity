# This takes the configuration defined in config/immunity_apps.rb and creates corresponding objects in the DB.
# This is the first version of defining an apps's configuration, so it may evolve to a configuration DSL,
# or we may start performing this configuration through UI and storing directly in the DB.
class ImmunityAppConfigParser
  def self.parse(config)
    config.keys.each do |app_name|
      app = Application.find_or_create(:name => app_name.to_s)
      regions = config[app_name][:regions]
      region_names = regions.map { |region| region[:name].to_s }
      app.regions.reject { |region| region_names.include?(region.name) }.each(&:destroy)

      regions.each.with_index do |region, index|
        db_region = Region.find_or_create(:name => region[:name], :application_id => app.id)
        db_region.host = region[:host]
        db_region.requires_manual_approval = (region[:manual_approval] == true)
      end
    end
  end
end
