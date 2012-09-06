require File.join(File.dirname(__FILE__), "migration_helper")

Sequel.migration do
  up do
    add_column :build_status, :region, String
    add_index :build_status, :region, :unique => true
  end

  down do
    drop_column :build_status, :region
  end
end
