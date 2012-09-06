require File.join(File.dirname(__FILE__), "migration_helper")

Sequel.migration do
  up do
    drop_column :builds, :is_test_build
    drop_column :builds, :repo
  end

  down do
    add_column :builds, :is_test_build, TrueClass, :default => false
    add_column :builds, :repo, String
  end
end
