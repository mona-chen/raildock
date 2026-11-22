require "rails_helper"

# Drills used to run `pg_isready` against a `dokku.postgres.*` container for
# every engine, so MySQL, MariaDB, MongoDB and Redis drills failed every week no
# matter how good the artifact was.
RSpec.describe RestoreDrillJob, "readiness probe" do
  subject(:job) { described_class.new }

  def probe(plugin)
    job.send(:readiness_command, plugin, "dokku.#{plugin}.raildock-drill-1-abc")
  end

  it "asks PostgreSQL with pg_isready" do
    expect(probe("postgres")).to eq("docker exec dokku.postgres.raildock-drill-1-abc pg_isready -U postgres")
  end

  it "pings MySQL and MariaDB with their admin clients" do
    expect(probe("mysql")).to include("dokku.mysql.raildock-drill-1-abc", "mysqladmin ping")
    expect(probe("mariadb")).to include("dokku.mariadb.raildock-drill-1-abc", "mariadb-admin ping")
  end

  it "pings MongoDB with mongosh, falling back to the legacy shell" do
    expect(probe("mongo")).to include("dokku.mongo.raildock-drill-1-abc", "mongosh", "|| mongo ")
  end

  it "checks Redis is running, since PING needs its password" do
    expect(probe("redis")).to include("docker inspect", "dokku.redis.raildock-drill-1-abc", "State.Running")
  end
end
