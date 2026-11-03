require "shellwords"

# Heal the specific Git object-directory ownership drift seen after a root-run
# fetch/restore. Never reset a repository or touch application data/object files.
class GitRepositoryPermissions
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
    if result[:success] && result[:output].to_s.lines.map(&:strip).include?("object_directories_repaired")
      @messages << "Repaired root-owned or unwritable Git object directories for #{app}; repository contents and application storage were left unchanged."
      true
    else
      reason = {
        "unsafe_repository" => "expected canonical bare repository could not be verified",
        "unsafe_objects" => "object store is missing or resolves through a symlink",
        "shared_objects" => "object store uses alternates, links or a mounted directory",
        "unexpected_owner" => "object directory belongs to an account other than root or dokku",
        "unsafe_lock" => "standard Dokku deploy-lock directory could not be verified",
        "deploy_locked" => "another deployment holds the app lock",
        "already_writable" => "all object directories are already writable; investigate ACLs, filesystem flags or host policy"
      }[result[:output].to_s.lines.map(&:strip).last] || "host could not safely repair object-directory permissions"
      skipped("Git permission recovery skipped: #{reason}. Check the Dokku host; no automatic sync retry was attempted.")
    end
  rescue => error
    skipped("Git permission recovery unavailable (#{error.class.name}); check the Dokku host.")
  end

  private

  def skipped(message)
    @messages << message
    false
  end

  def repair_script(app)
    <<~SH
      set -eu
      app=#{Shellwords.escape(app)}
      dokku_home=$(getent passwd dokku | cut -d: -f6)
      uid=$(id -u dokku)
      gid=$(id -g dokku)
      case "$dokku_home" in /*) ;; *) echo unsafe_repository; exit 1 ;; esac
      test "$dokku_home" != / || { echo unsafe_repository; exit 1; }
      repo="$dokku_home/$app"
      test -d "$repo" && test ! -L "$repo" && test "$(realpath -e -- "$repo")" = "$repo" || { echo unsafe_repository; exit 1; }
      test "$(runuser -u dokku -- git --git-dir="$repo" rev-parse --is-bare-repository)" = true || { echo unsafe_repository; exit 1; }
      objects="$repo/objects"
      test -d "$objects" && test ! -L "$objects" && test "$(realpath -e -- "$objects")" = "$objects" || { echo unsafe_objects; exit 1; }
      lock_dir="/var/lib/dokku/data/apps/$app"
      test -d "$lock_dir" && test "$(realpath -e -- "$lock_dir")" = "$lock_dir" && test ! -L "$lock_dir/.deploy.lock" || { echo unsafe_lock; exit 1; }
      # Create the lock as dokku, never root: recovery must not create the next
      # permissions incident. Use the same advisory lock as Dokku deployments.
      runuser -u dokku -- touch -- "$lock_dir/.deploy.lock"
      exec 9>>"$lock_dir/.deploy.lock"
      flock -n 9 || { echo deploy_locked; exit 1; }
      test ! -s "$objects/info/alternates" && test ! -s "$objects/info/http-alternates" || { echo shared_objects; exit 1; }
      linked=$(find "$objects" -xdev -type l -print -quit)
      mounted=$(find "$objects" -xdev -type d -exec mountpoint -q -- {} \\; -print -quit)
      test -z "$linked$mounted" || { echo shared_objects; exit 1; }
      unusual=$(find "$objects" -xdev -type d ! -uid 0 ! -uid "$uid" -print -quit)
      test -z "$unusual" || { echo unexpected_owner; exit 1; }
      blocked=$(runuser -u dokku -- find "$objects" -xdev -type d ! -writable -print -quit)
      test -n "$blocked" || { echo already_writable; exit 1; }
      # Object files are intentionally immutable/read-only in Git. Fix directory
      # metadata only, preserving object bytes, file modes, refs, config and hooks.
      find "$objects" -xdev -type d -uid 0 -exec chown --from=0 -- "$uid:$gid" {} +
      find "$objects" -xdev -type d -uid "$uid" -exec chmod u+rwx -- {} +
      blocked=$(runuser -u dokku -- find "$objects" -xdev -type d ! -writable -print -quit)
      test -z "$blocked"
      echo object_directories_repaired
    SH
  end
end
