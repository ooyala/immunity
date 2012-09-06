require File.join(File.dirname(__FILE__), "migration_helper")

Sequel.migration do
  up do
    alter_table(:build_status) do
      drop_index :build_id
      drop_index :region
      add_index [:build_id, :region]
    end
  end

  down do
      add_index :build_id
      add_index :region

      drop_index [:build_id, :region]

  end
end
