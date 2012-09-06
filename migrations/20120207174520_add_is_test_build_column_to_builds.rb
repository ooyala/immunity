require File.join(File.dirname(__FILE__), "migration_helper")

Sequel.migration do
  up do
    add_column :builds, :is_test_build, TrueClass, :default => false
  end

  down do
    drop_column :builds, :is_test_build
  end
end
