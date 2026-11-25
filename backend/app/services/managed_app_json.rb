require "base64"
require "shellwords"

# Versioned bridge for settings whose native Dokku home is app.json. No script is
# executed by Rails: Dokku validates and executes the merged release declaration.
class ManagedAppJson
  DIRECTORY = Rails.root.join("lib/raildock/dokku-managed")

  def initialize(service, host_engine)
    @service = service
    @host_engine = host_engine
  end

  def declaration
    config = @service.config || {}
    result = {}
    result["cron"] = Array(config["cron"]) if config.key?("cron")
    checks = config["checks"] || {}
    if config.key?("checks")
      if checks["enabled"] != false && !%w[disabled skipped].include?(checks["mode"])
        check = { "type" => "startup", "name" => "RailDock readiness", "path" => checks["path"].presence || "/", "port" => @service.effective_port }
        %w[wait timeout attempts initialDelay].each { |key| check[key] = checks[key].to_i if checks[key].present? }
        result["healthchecks"] = { "web" => [ check ] }
      else
        # An explicit empty list clears the web check without touching checks
        # a repository declaration may define for other process types.
        result["healthchecks"] = { "web" => [] }
      end
    end
    scripts = config["scripts"] || {}
    if config.key?("scripts") && !(scripts["source"] == "repository" && scripts["format"] == "app.json")
      # Blank phases are explicit removals: they clear a stale RailDock value
      # without discarding an unrelated repository phase under scripts.dokku.
      result["scripts"] = %w[predeploy postdeploy].index_with { |phase| scripts[phase].to_s }
    end
    result
  end

  def apply!
    files = %w[merge.py pre-release-builder plugin.toml].to_h { |name| [ name, File.read(DIRECTORY.join(name)) ] }
    payload = Base64.strict_encode64({ app: @service.dokku_app_name, declaration: declaration, files: files }.to_json)
    # All names and paths are fixed, or validated inside the host installer.
    script = <<~PYTHON
      import base64,json,os,pathlib,re,subprocess,tempfile
      data=json.loads(base64.b64decode(#{payload.to_json}))
      version=subprocess.check_output(['dokku','version'],text=True).strip()
      if not re.search(r'(?<![0-9])0[.]38[.][0-9]+',version):
          raise RuntimeError('Managed lifecycle settings require tested Dokku 0.38.x')
      app=data['app']
      if not re.fullmatch(r'[a-z0-9][a-z0-9.-]*',app): raise RuntimeError('Invalid app name')
      home=pathlib.Path('/home/dokku')
      if not home.is_dir(): raise RuntimeError('Dokku user home is missing')
      account=home.stat()
      plugin=pathlib.Path('/var/lib/dokku/plugins/available/00-raildock-managed')
      plugin.mkdir(parents=True,exist_ok=True)
      for name,content in data['files'].items():
          target=plugin/name
          with tempfile.NamedTemporaryFile(dir=plugin,delete=False) as stream:
              stream.write(content.encode()); temporary=stream.name
          os.chmod(temporary,0o755 if name in ('merge.py','pre-release-builder') else 0o644)
          os.replace(temporary,target)
      enabled=pathlib.Path('/var/lib/dokku/plugins/enabled/00-raildock-managed')
      if not enabled.exists(): enabled.symlink_to(plugin)
      directory=pathlib.Path('/var/lib/dokku/data/raildock-managed')
      directory.mkdir(parents=True,exist_ok=True)
      os.chown(directory,account.st_uid,account.st_gid)
      os.chmod(directory,0o700)
      with tempfile.NamedTemporaryFile(dir=directory,delete=False) as stream:
          stream.write(json.dumps(data['declaration']).encode()); temporary=stream.name
      os.chown(temporary,account.st_uid,account.st_gid)
      os.chmod(temporary,0o600)
      os.replace(temporary,directory/(app+'.json'))
    PYTHON
    encoded_script = Base64.strict_encode64(script)
    result = @host_engine.run("printf %s #{Shellwords.escape(encoded_script)} | base64 -d | python3")
    raise ServiceSettingsSync::ApplyError, "Could not prepare native Dokku lifecycle settings. #{LogRedactor.redact(result[:output].to_s).truncate(400)}" unless result[:success]
    result
  end
end
