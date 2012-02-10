require "./" + File.join(File.dirname(__FILE__), "migration_helper")

Sequel.migration do
  up do
    rename_table :build_status, :build_statuses
  end

  down do
    rename_table :build_statuses, :build_status
  end
end
