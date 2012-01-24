require "./" + File.join(File.dirname(__FILE__), "migration_helper")

Sequel.migration do
  up do
    create_table(:builds) do
      primary_key :id
      datetime :created_at
      datetime :updated_at
      String :state, :null => false
      String :commit
      String :current_region
      String :approved_by
      datetime :approved_at

      index [:state, :id], :unique => true
    end
  end

  down do
    drop_table(:builds)
  end
end
