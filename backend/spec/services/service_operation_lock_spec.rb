require "rails_helper"
require "pg"

RSpec.describe ServiceOperationLock do
  # Transactional Rails fixtures intentionally pin one connection across test
  # threads, so use a separate PostgreSQL session to test real exclusion.
  def independent_connection
    config = ApplicationRecord.connection_db_config.configuration_hash
    PG.connect(dbname: config[:database], host: config[:host], port: config[:port], user: config[:username], password: config[:password])
  end

  it "excludes another session and releases the lock after exceptions" do
    service = Service.new(id: 987654321)
    connection = independent_connection
    sql = "SELECT pg_try_advisory_lock(hashtextextended('raildock:service:#{service.id}', 0))"
    described_class.with(service) { expect(connection.exec(sql).getvalue(0, 0)).to eq("f") }
    expect { described_class.with(service) { raise "interrupted" } }.to raise_error("interrupted")
    expect(connection.exec(sql).getvalue(0, 0)).to eq("t")
  ensure
    connection&.close # Closing also releases that session's successful probe lock.
  end

  it "excludes service operations while the project is being destroyed" do
    project = Project.new(id: 987654321)
    connection = independent_connection
    sql = "SELECT pg_try_advisory_lock_shared(hashtextextended('raildock:project:#{project.id}', 0))"
    described_class.with_project(project, exclusive: true) do
      expect(connection.exec(sql).getvalue(0, 0)).to eq("f")
    end
    expect(connection.exec(sql).getvalue(0, 0)).to eq("t")
  ensure
    connection&.close
  end
end
