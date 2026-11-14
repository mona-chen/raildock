require "shellwords"

# Heal the specific Git object-directory ownership drift seen after a root-run
# fetch/restore. Never reset a repository or touch application data/object files.
class GitRepositoryPermissions
  REPAIRED_MARKER = "object_directories_repaired".freeze
  LOG_OUTPUT_LIMIT = 2_000

  # Every exit path of the repair script must print exactly one of these tokens.
  # Anything else means the script died before it could classify itself.
  REASONS = {
    "unsafe_repository" => "expected canonical bare repository could not be verified",
    "unsafe_objects" => "object store is missing or resolves through a symlink",
    "shared_objects" => "object store uses alternates, links or a mounted directory",
    "unexpected_owner" => "object directory belongs to an account other than root or dokku",
    "unsafe_lock" => "standard Dokku deploy-lock directory could not be verified",
    "deploy_locked" => "another deployment holds the app lock",
    "already_writable" => "all object directories are already writable; investigate ACLs, filesystem flags or host policy",
    "repair_incomplete" => "object directories are still not writable for dokku after the repair",
    "unexpected_failure" => "the recovery script aborted before reporting a reason"
  }.freeze

  attr_reader :messages

  def self.permission_error?(output)
    output.to_s.match?(/insufficient permission for adding an object to repository database/i)
  end

  def initialize(service, host_engine:)
    @service, @host, @messages = service, host_engine, []
  end

  def repair
    app = @service.dokku_app_name.to_s
    return skipped("Invalid Dokku app name; no permissions changed.") unless app.match?(/\A[a-z0-9][a-z0-9-]{0,62}\z/)

    result = @host.run(repair_script(app))
    markers = markers_for(result[:output])

    if result[:success] && markers.include?(REPAIRED_MARKER)
      @messages << "Repaired root-owned or unwritable Git object directories for #{app}; repository contents and application storage were left unchanged."
      true
    else
      log_unclassified(app, result[:output]) if (markers & REASONS.keys).empty?
      skipped("Git permission recovery skipped: #{reason_for(markers)}. Check the Dokku host; no automatic sync retry was attempted.")
    end
  rescue => error
    skipped("Git permission recovery unavailable (#{error.class.name}); check the Dokku host.")
  end

  private

  def skipped(message)
    @messages << message
    false
  end

  def markers_for(output)
    output.to_s.lines.map(&:strip).reject(&:empty?)
  end

  # HostEngine merges stderr into stdout, so a diagnostic line can legitimately
  # follow the reason marker. Classify by scanning the whole stream rather than
  # trusting the last line, which silently degraded every case to the fallback.
  def reason_for(markers)
    marker = markers.reverse.find { |line| REASONS.key?(line) }
    REASONS.fetch(marker, "host could not safely repair object-directory permissions")
  end

  # Host output stays out of user-facing messages because it can contain paths
  # and credentials, but an unclassified abort is undiagnosable without it.
  def log_unclassified(app, output)
    detail = output.to_s.gsub(/\s+/, " ").strip
    detail = "#{detail[0, LOG_OUTPUT_LIMIT]}..." if detail.length > LOG_OUTPUT_LIMIT
    detail = "(no output)" if detail.empty?
    Rails.logger.warn("Git permission recovery produced no recognised marker for #{app}: #{detail}")
  end

  def repair_script(app)
    <<~SH
      set -eu
      emitted=""
      emit() { emitted=1; printf '%s\\n' "$1"; }
      fail() { emit "$1"; exit 1; }
      trap 'status=$?; if [ -z "$emitted" ]; then emit unexpected_failure; printf "git permission recovery aborted (status=%s line=%s)\\n" "$status" "${LINENO:-?}" >&2; fi; exit "$status"' EXIT
      app=#{Shellwords.escape(app)}
      dokku_home=$(getent passwd dokku | cut -d: -f6)
      uid=$(id -u dokku)
      gid=$(id -g dokku)
      case "$dokku_home" in /*) ;; *) fail unsafe_repository ;; esac
      test "$dokku_home" != / || fail unsafe_repository
      repo="$dokku_home/$app"
      test -d "$repo" && test ! -L "$repo" && test "$(realpath -e -- "$repo")" = "$repo" || fail unsafe_repository
      test "$(runuser -u dokku -- git --git-dir="$repo" rev-parse --is-bare-repository)" = true || fail unsafe_repository
      objects="$repo/objects"
      test -d "$objects" && test ! -L "$objects" && test "$(realpath -e -- "$objects")" = "$objects" || fail unsafe_objects
      lock_dir="/var/lib/dokku/data/apps/$app"
      test -d "$lock_dir" && test "$(realpath -e -- "$lock_dir")" = "$lock_dir" && test ! -L "$lock_dir/.deploy.lock" || fail unsafe_lock
      # Create the lock as dokku, never root: recovery must not create the next
      # permissions incident. Use the same advisory lock as Dokku deployments.
      runuser -u dokku -- touch -- "$lock_dir/.deploy.lock"
      exec 9>>"$lock_dir/.deploy.lock"
      flock -n 9 || fail deploy_locked
      test ! -s "$objects/info/alternates" && test ! -s "$objects/info/http-alternates" || fail shared_objects
      linked=$(find "$objects" -xdev -type l -print -quit)
      mounted=$(find "$objects" -xdev -type d -exec mountpoint -q -- {} \\; -print -quit)
      test -z "$linked$mounted" || fail shared_objects
      unusual=$(find "$objects" -xdev -type d ! -uid 0 ! -uid "$uid" -print -quit)
      test -z "$unusual" || fail unexpected_owner
      blocked=$(runuser -u dokku -- find "$objects" -xdev -type d ! -writable -print -quit)
      test -n "$blocked" || fail already_writable
      # Object files are intentionally immutable/read-only in Git. Fix directory
      # metadata only, preserving object bytes, file modes, refs, config and hooks.
      find "$objects" -xdev -type d -uid 0 -exec chown --from=0 -- "$uid:$gid" {} +
      find "$objects" -xdev -type d -uid "$uid" -exec chmod u+rwx -- {} +
      blocked=$(runuser -u dokku -- find "$objects" -xdev -type d ! -writable -print -quit)
      test -z "$blocked" || fail repair_incomplete
      emit object_directories_repaired
    SH
  end
end
