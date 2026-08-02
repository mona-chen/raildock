require "rails_helper"

RSpec.describe DatabaseViewer, type: :service do
  let(:postgres_service) { create(:service, :database, subtype: "postgres", dokku_app_name: "proj-pg") }
  let(:engine) { double("engine") }

  subject(:viewer) { described_class.new(postgres_service, engine) }

  # Canned datastore_query responses, consumed in order.
  def stub_outputs(*outputs)
    allow(engine).to receive(:datastore_query) do |_service, _sql|
      out = outputs.shift
      out.nil? ? { success: true, output: "[]" } : out
    end
  end

  describe "#supported?" do
    it "is true for postgres" do
      expect(viewer.supported?).to be true
    end

    it "is false for redis" do
      redis = described_class.new(create(:service, service_type: :cache, subtype: "redis"), engine)
      expect(redis.supported?).to be false
    end
  end

  describe "#tables" do
    it "parses the postgres JSON payload" do
      stub_outputs({ success: true, output: %([{"name":"users","schema":"public"},{"name":"orders","schema":"public"}]) })

      expect(viewer.tables).to eq([
        { "name" => "users", "schema" => "public" },
        { "name" => "orders", "schema" => "public" }
      ])
    end

    it "joins a long JSON payload split across many psql continuation lines" do
      rows = [ { "name" => "users", "schema" => "public" }, { "name" => "orders", "schema" => "public" } ]
      wrapped = rows.to_json.gsub(/, /, ",\n {")
      stub_outputs({ success: true, output: "Output format is unaligned.\nTuples only is on.\n#{wrapped}\n" })

      expect(viewer.tables).to eq(rows)
    end

    it "raises Auth (not QueryFailed) when the datastore rejects our credentials" do
      stub_outputs({ success: false, error: 'ERROR 1045 (28000): Access denied \u00a8user\u00a8mysql\u00a8\u00a8localhost' })
      expect { viewer.tables }.to raise_error(DatabaseViewer::Auth)
    end

    it "raises Auth on postgres password-authentication failures" do
      stub_outputs({ success: false, error: "FATAL: password authentication failed for user 'mysql'" })
      expect { viewer.tables }.to raise_error(DatabaseViewer::Auth)
    end

    it "raises Unsupported for non-SQL datastores" do
      redis = described_class.new(create(:service, service_type: :cache, subtype: "redis"), engine)
      expect { redis.tables }.to raise_error(DatabaseViewer::Unsupported)
    end

    it "surfaces query failures" do
      stub_outputs({ success: false, error: "relation does not exist" })
      expect { viewer.tables }.to raise_error(DatabaseViewer::QueryFailed, "relation does not exist")
    end
  end

  describe "#rows" do
    it "returns columns, rows and pagination metadata" do
      stub_outputs(
        { success: true, output: %([{"name":"id","type":"integer"},{"name":"name","type":"character varying"}]) },
        { success: true, output: %([{"id":1,"name":"Alice"},{"id":2,"name":"Bob"}]) }
      )

      result = viewer.rows("users", limit: 50, offset: 0)
      expect(result[:columns]).to eq([
        { "name" => "id", "type" => "integer" },
        { "name" => "name", "type" => "character varying" }
      ])
      expect(result[:rows]).to eq([ { "id" => 1, "name" => "Alice" }, { "id" => 2, "name" => "Bob" } ])
      expect(result[:limit]).to eq(50)
      expect(result[:offset]).to eq(0)
      expect(result[:has_more]).to be false
    end

    it "flags has_more when a full page is returned" do
      rows = Array.new(50) { |i| { "id" => i } }
      stub_outputs(
        { success: true, output: %([{"name":"id","type":"integer"}]) },
        { success: true, output: rows.to_json }
      )

      expect(viewer.rows("users", limit: 50, offset: 0)[:has_more]).to be true
    end

    it "clamps the limit to the max page size" do
      stub_outputs(
        { success: true, output: %([{"name":"id","type":"integer"}]) },
        { success: true, output: "[]" }
      )

      result = viewer.rows("users", limit: 5000, offset: 0)
      expect(result[:limit]).to eq(DatabaseViewer::MAX_LIMIT)
    end

    it "rejects blank table names" do
      expect { viewer.rows("") }.to raise_error(DatabaseViewer::Error)
    end

    it "quotes identifiers with embedded double quotes for postgres" do
      calls = []
      allow(engine).to receive(:datastore_query) do |_service, sql|
        calls << sql
        if sql.include?("information_schema.columns")
          { success: true, output: %([{"name":"id","type":"integer"}]) }
        else
          { success: true, output: "[]" }
        end
      end

      viewer.rows('weird " name', limit: 1, offset: 0)
      expect(calls.last).to include('FROM "weird "" name"')
    end
  end

  describe "MySQL output parsing" do
    let(:mysql_service) { create(:service, :database, subtype: "mysql", dokku_app_name: "proj-mysql") }
    subject(:mysql_viewer) { described_class.new(mysql_service, engine) }

    it "extracts the JSON payload from the boxed client output" do
      boxed = <<~OUT
        +----------------------------------------+
        | _raildock_json                          |
        +----------------------------------------+
        | [{"id":1,"name":"Alice"}]               |
        +----------------------------------------+
      OUT
      allow(engine).to receive(:datastore_query).and_return({ success: true, output: boxed })

      expect(mysql_viewer.tables).to eq([ { "id" => 1, "name" => "Alice" } ])
    end

    it "returns an empty array when the payload is NULL" do
      boxed = <<~OUT
        +-----------------+
        | _raildock_json  |
        +-----------------+
        | NULL            |
        +-----------------+
      OUT
      allow(engine).to receive(:datastore_query).and_return({ success: true, output: boxed })

      expect(mysql_viewer.tables).to eq([])
    end

    it "parses the non-interactive batch format as dokku connect emits it" do
      batch = <<~OUTPUT
        _raildock_json
        [{"name":"users","schema":"skillmango_mariadb"},{"name":"orders","schema":"skillmango_mariadb"}]
      OUTPUT
      allow(engine).to receive(:datastore_query).and_return({ success: true, output: batch })

      expect(mysql_viewer.tables).to eq([
        { "name" => "users", "schema" => "skillmango_mariadb" },
        { "name" => "orders", "schema" => "skillmango_mariadb" }
      ])
    end
  end
end
