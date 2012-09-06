require File.join(File.dirname(__FILE__), "migration_helper")

Sequel.migration do
  up do
    add_column :build_statuses, :created_at, DateTime
  end

  down do
    drop_column :build_statuses, :created_at
  end
end
