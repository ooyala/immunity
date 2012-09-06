require File.join(File.dirname(__FILE__), "migration_helper")

Sequel.migration do
  up do
    add_column :applications, :deploy_command, String, :size => 1024
    add_column :applications, :test_command, String, :size => 1024
  end

  down do
    drop_column :applications, :deploy_command
    drop_column :applications, :test_command
  end
end
