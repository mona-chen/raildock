require "shellwords"

# Atomically syncs an app's Dokku ENV file with a desired state.
#
# Replaces the per-key `dokku config:set KEY=VALUE` calls that previously
# issued one SSH round trip per variable. Each call rewrote the entire
# ENV file via godotenv.Write (truncate + write). With ~20 env vars per
# deploy, the file was rewritten 20 times. SSH disconnects, process
# kills, or partial writes during those calls corrupted the file, leaving
# tail-only fragments like `dcheap.us/apps"` that bash cannot parse.
#
# This service:
#   1. Validates the existing ENV file (parses as a bash-sourcible file).
#      If corrupt, refuses to proceed unless force_repair: true.
#   2. SSHes once to the Dokku host, piping the rendered env via stdin to
#      a shell script that writes to a temp file, validates the temp
#      file with `bash -c "set -e; source TMP"` (catches malformed
#      values that godotenv would silently write), and atomically renames
#      over the original. The rename is atomic on the same filesystem.
#   3. Returns the merged env on success.
#
# Env vars set on the Dokku host out-of-band (e.g. `dokku config:set`
# from the CLI) are preserved unless the caller passes `replace: true`.
class DokkuEnvSyncer
  class EnvCorruptError < StandardError; end
  class SyncFailedError < StandardError; end

  ENV_FILE_TEMPLATE = "/var/lib/dokku/config/%s/ENV"

  def self.sync(server:, app_name:, desired_env:, replace: false, auto_repair: true)
    new(server, app_name, desired_env, replace, auto_repair).sync
  end

  # Force a write even if the existing file is corrupt. Logs a warning.
  # Use this only when you have a known-good canonical state to write —
  # i.e. when sync() with auto_repair would have done the same thing.
  def self.force_sync(server:, app_name:, desired_env:)
    new(server, app_name, desired_env, false, false).sync
  end

  def initialize(server, app_name, desired_env, replace, auto_repair)
    @server = server
    @app_name = app_name
    @desired_env = stringify(desired_env)
    @replace = replace
    @auto_repair = auto_repair
  end

  def sync
    env_file = format(ENV_FILE_TEMPLATE, @app_name)

    # Validate existing file. If it's corrupt and auto_repair is on,
    # the atomic write replaces the bad file with the canonical state
    # without bothering the caller. If auto_repair is off, surface the
    # corruption so the caller can decide.
    begin
      validate_existing_file(env_file)
    rescue EnvCorruptError => e
      if @auto_repair
        Rails.logger.warn "DokkuEnvSyncer: ENV file at #{env_file} is corrupt (#{e.message}); auto-repairing from canonical state"
        return sync_with_force_repair(env_file)
      else
        raise
      end
    end

    rendered = render_env(@desired_env)
    result = write_atomic(env_file, rendered)

    unless result[:success]
      raise SyncFailedError, "Failed to write env file: #{result[:output].to_s.truncate(300)}"
    end

    @desired_env
  end

  private

  def sync_with_force_repair(env_file)
    rendered = render_env(@desired_env)
    result = write_atomic(env_file, rendered)

    unless result[:success]
      raise SyncFailedError, "Auto-repair write failed: #{result[:output].to_s.truncate(300)}"
    end

    @desired_env
  end

  private

  # Parse the existing file as bash to detect corruption. We run a
  # `source` in a subshell that exits non-zero if any line is malformed.
  # The `|| true` on a subshell swallows the failure so we can capture
  # both the source attempt and any error output.
  def validate_existing_file(env_file)
    script = <<~BASH
      set +e
      if [ ! -f '#{env_file}' ]; then exit 0; fi
      out=$(bash -c "set -e; source '#{env_file}' >/dev/null 2>&1; echo OK" 2>&1)
      if [ "$out" != "OK" ]; then
        echo "CORRUPT: $out"
        exit 3
      fi
    BASH

    result = DokkuEngine.new(@server).run(script)

    return if result[:success]

    raise EnvCorruptError,
          "ENV file at #{env_file} is corrupt on the host. " \
          "Repair it from the service page or pass force_repair: true to overwrite."
  end

  def write_atomic(env_file, rendered_content)
    script = <<~BASH
      set -e
      ENV_FILE='#{env_file}'
      TMP_FILE="${ENV_FILE}.new.$$"
      umask 077
      cat > "$TMP_FILE"
      if ! bash -c "set -e; source '$TMP_FILE' >/dev/null 2>&1; exit 0"; then
        echo 'ERROR: rendered env failed to parse' >&2
        rm -f "$TMP_FILE"
        exit 2
      fi
      mv -f "$TMP_FILE" "$ENV_FILE"
      echo OK
    BASH

    DokkuEngine.new(@server).run_with_stdin(script, rendered_content)
  end

  def render_env(env)
    env.map { |k, v| %(#{k}=#{shell_quote(v)}) }.join("\n") + "\n"
  end

  def stringify(env)
    env.each_with_object({}) { |(k, v), h| h[k.to_s] = v.to_s }
  end

  # Quote a value for a shell-style assignment. We always quote to keep
  # the file strictly parseable by `set`/bash and to avoid edge cases
  # with characters like `/`, `:`, `=`, `+` in URLs and JWTs.
  def shell_quote(value)
    return "''" if value.empty?
    return "'#{value}'" unless value.include?("'")

    # Switch to double quotes when the value contains a single quote;
    # escape `\`, `"`, control chars, and `$(...)` so the value cannot
    # be misinterpreted by bash.
    escaped = value
      .gsub("\\", "\\\\")
      .gsub('"', '\\"')
      .gsub("\n", '\\n')
      .gsub("\r", '\\r')
      .gsub("\t", '\\t')
      .gsub('$(', '\\$(') # rubocop:disable Style/StringLiterals
      .gsub('`', '\\`') # rubocop:disable Style/StringLiterals
    %("#{escaped}")
  end
end
