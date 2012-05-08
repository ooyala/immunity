require "./" + File.join(File.dirname(__FILE__), "migration_helper")

Sequel.migration do
  up do
    add_column :regions, :requires_monitoring, TrueClass, :null => false
  end

  down do
    drop_column :regions, :requires_monitoring
  end
end
