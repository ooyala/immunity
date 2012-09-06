require File.join(File.dirname(__FILE__), "migration_helper")

Sequel.migration do
  up do
    # This is not a production safe way to reshuffle these columns, but we're not in production yet.
    DB[:builds].delete
    DB[:build_statuses].delete

    drop_column :build_statuses, :region
    drop_column :builds, :current_region, :null => false
    add_column :builds, :current_region_id, Integer, :null => false
    add_column :build_statuses, :region_id, TrueClass, :default => false
    add_index :build_statuses, :region_id
    add_index :builds, :current_region_id
  end

  down do

  end
end
