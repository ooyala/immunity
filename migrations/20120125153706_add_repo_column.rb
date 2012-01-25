require "./" + File.join(File.dirname(__FILE__), "migration_helper")

Sequel.migration do
  up do
    add_column :builds, :repo, String
  end

  down do
    drop_column :builds, :repo
  end
end
