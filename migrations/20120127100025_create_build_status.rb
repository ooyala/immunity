require "./" + File.join(File.dirname(__FILE__), "migration_helper")

Sequel.migration do
  up do
    create_table(:build_status) do
      primary_key :id
      Integer :build_id
      datetime :updated_at
      text :stdout
      text :stderr
      text :message

      index [:build_id], :unique => true
    end
  end

  down do
    drop_table(:build_status)
  end
end
