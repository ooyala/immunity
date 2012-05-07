require "./" + File.join(File.dirname(__FILE__), "migration_helper")

Sequel.migration do
  up do
    # This column will help us specify the explicit order of the regions when deploying.
    add_column :regions, :ordinal, Integer, :null => false
  end

  down do
    drop_column :regions, :ordinal
  end
end
