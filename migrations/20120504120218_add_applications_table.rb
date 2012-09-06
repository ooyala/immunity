require File.join(File.dirname(__FILE__), "migration_helper")

Sequel.migration do
  up do
    create_table(:applications) do
      primary_key :id
      datetime :created_at
      datetime :updated_at
      String :name, :null => false
      Boolean :active, :null => false, :default => true
      # Test apps can take shortcuts through the build cycle, which is useful for integration tests.
      Boolean :is_test, :null => false, :default => false
    end
  end

  down do
    drop_table(:applications)
  end
end
