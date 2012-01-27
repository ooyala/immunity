class BuildStatus < Sequel::Model(:build_status)
  many_to_one :build
end