require "./" + File.join(File.dirname(__FILE__), "migration_helper")

Sequel.migration do
  up do
    create_table(:regions) do
      primary_key :id
      datetime :created_at
      datetime :updated_at
      String :name, :null => false
      String :host, :null => false
      Integer :application_id, :null => false
      Boolean :requires_manual_approval, :null => false, :default => true
      index :application_id
    end
  end

  down do
    drop_table(:regions)
  end
end
