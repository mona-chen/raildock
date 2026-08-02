# frozen_string_literal: true

# Read-only database inspection backed by Dokku's datastore `connect` commands.
#
# RailDock talks to datastores over SSH as the `dokku` user. Dokku's connect
# commands run the database CLI inside the service container with stdin
# attached, so we pipe engine-specific SQL scripts through and parse the client
# output into structured hashes. No user-supplied SQL is ever executed — table
# and column names are validated and quoted server-side.
class DatabaseViewer
  MAX_LIMIT = 200
  DEFAULT_LIMIT = 50
  MAX_TABLE_NAME_LENGTH = 200

  class Error < StandardError; end
  class Unsupported < Error; end
  class QueryFailed < Error; end

  # Raised when the datastore rejects our credentials. This is almost always a
  # credential-drift situation: the live database's users no longer match what
  # Dokku/RailDock have stored (e.g. passwords rotated out of band). It is
  # surfaced to the UI as an actionable "out of sync" state rather than a
  # generic query failure so the client stops retrying.
  class Auth < Error; end

  SQL_ENGINES = %w[postgres mysql mariadb].freeze

  def initialize(service, engine)
    @service = service
    @engine = engine
    @subtype = service.subtype.to_s
  end

  def supported?
    SQL_ENGINES.include?(@subtype) && PluginRegistry.has_capability?(@subtype, :query)
  end

  def tables
    ensure_supported!
    parse_json(run_sql(tables_sql))
  end

  def rows(table, limit: DEFAULT_LIMIT, offset: 0)
    ensure_supported!
    name = normalize_table_name(table)
    lim = (limit || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
    off = [ offset.to_i, 0 ].max

    columns = parse_json(run_sql(columns_sql(name)))
    data = columns.empty? ? [] : parse_json(run_sql(rows_sql(name, columns, lim, off)))

    {
      table: name,
      columns: columns,
      rows: data,
      limit: lim,
      offset: off,
      has_more: data.size >= lim
    }
  end

  private

  def ensure_supported!
    raise Unsupported, "Database viewer is not supported for #{@subtype}" unless supported?
  end

  # Run a script through the datastore client and return raw stdout.
  def run_sql(sql)
    script = @subtype == "postgres" ? "\\a\n\\t\n#{sql}\n" : sql
    result = @engine.datastore_query(@service, script)
    return result[:output] if result[:success]

    classify_failure(result[:error].presence || "Query failed")
  end

  # Accepts a raw failure message (from DatastoreError output or the engine's
  # `error` field) and raises the right error class so callers can tell a
  # credential/auth problem apart from a plain query failure.
  def classify_failure(message)
    raise Auth, message if auth_failure?(message.to_s)

    raise QueryFailed, message
  end

  def auth_failure?(message)
    message.match?(/Access denied|using password:\s*YES|ERROR\s+1045|\(28000\)|password authentication failed|Peer authentication failed|pg_hba/i)
  end

  # Every payload query is crafted to emit a single JSON value.
  def parse_json(output)
    if mysql_family?
      extract_mysql_json(output)
    else
      JSON.parse(extract_json_payload(output))
    end
  rescue JSON::ParserError
    raise QueryFailed, "Could not parse database response"
  end

  # psql wraps a long json_agg value over many continuation lines regardless of
  # `\a`/`\t`, so the whole JSON envelope is the payload: everything from the
  # first `[`/`{` to the last `]`/`}` is joined and parsed. Truncating to the
  # first line (as some naive parsers do) silently loses the rest of the value.
  def extract_json_payload(output)
    start_idx = output.index(/[\[{]/)
    end_idx = output.rindex(/[\]}]/)
    return output.strip if start_idx.nil? || end_idx.nil? || start_idx > end_idx

    output[start_idx..end_idx]
  end

  def mysql_family?
    %w[mysql mariadb].include?(@subtype)
  end

  # MySQL/MariaDB clients print an ASCII box. Each query returns a single JSON
  # payload row; the boxed row is the last `| ... |` line before the closing
  # border, and mysql escapes newlines inside values so the payload stays whole.
  def extract_mysql_json(output)
    cell = output.lines.select { |l| l.start_with?("| ") }
                      .map { |l| l.sub(/\A\|\s*/, "").sub(/\s*\|\s*\z/, "") }
                      .last.to_s.strip
    return [] if cell.empty? || cell == "NULL"

    JSON.parse(cell)
  end

  def normalize_table_name(raw)
    name = raw.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").delete("\x00")
    raise Error, "Invalid table name" if name.empty? || name.length > MAX_TABLE_NAME_LENGTH

    name
  end

  # Quote a database identifier for the current engine.
  def q(identifier)
    case @subtype
    when "postgres"
      %("#{identifier.gsub('"', '""')}")
    else
      "`#{identifier.gsub('`', '``')}`"
    end
  end

  # Single-quoted SQL string literal (both engines escape ' by doubling).
  def l(value)
    "'#{value.to_s.gsub("'", "''")}'"
  end

  def tables_sql
    case @subtype
    when "postgres"
      "SELECT COALESCE(json_agg(t), '[]'::json) FROM (" \
        "SELECT table_name AS name, table_schema AS schema FROM information_schema.tables " \
        "WHERE table_schema = current_schema() AND table_type = 'BASE TABLE' ORDER BY table_name" \
      ") t"
    else
      "SELECT COALESCE(JSON_ARRAYAGG(JSON_OBJECT('name', TABLE_NAME, 'schema', TABLE_SCHEMA)), JSON_ARRAY()) AS _raildock_json FROM (" \
        "SELECT TABLE_NAME, TABLE_SCHEMA FROM information_schema.tables " \
        "WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE' ORDER BY TABLE_NAME" \
      ") x"
    end
  end

  def columns_sql(table)
    case @subtype
    when "postgres"
      "SELECT COALESCE(json_agg(t), '[]'::json) FROM (" \
        "SELECT column_name AS name, data_type AS type FROM information_schema.columns " \
        "WHERE table_schema = current_schema() AND table_name = #{l(table)} ORDER BY ordinal_position" \
      ") t"
    else
      "SELECT COALESCE(JSON_ARRAYAGG(JSON_OBJECT('name', COLUMN_NAME, 'type', DATA_TYPE)), JSON_ARRAY()) AS _raildock_json FROM (" \
        "SELECT COLUMN_NAME, DATA_TYPE FROM information_schema.columns " \
        "WHERE table_schema = DATABASE() AND table_name = #{l(table)} ORDER BY ORDINAL_POSITION" \
      ") x"
    end
  end

  def rows_sql(table, columns, limit, offset)
    case @subtype
    when "postgres"
      "SELECT COALESCE(json_agg(t), '[]'::json) FROM " \
        "(SELECT * FROM #{q(table)} LIMIT #{limit} OFFSET #{offset}) t"
    else
      pairs = Array(columns).map { |c| "#{l(c["name"])}, #{q(c["name"])}" }.join(", ")
      "SELECT COALESCE(JSON_ARRAYAGG(JSON_OBJECT(#{pairs})), JSON_ARRAY()) AS _raildock_json FROM " \
        "(SELECT * FROM #{q(table)} LIMIT #{limit} OFFSET #{offset}) x"
    end
  end
end
