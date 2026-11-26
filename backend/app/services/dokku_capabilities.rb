# Discover installed command namespaces rather than assuming optional plugins.
class DokkuCapabilities
  def initialize(engine)
    @engine = engine
  end

  def read
    result = @engine.run("help")
    raise ServiceSettingsSync::ApplyError, "Could not discover host capabilities" unless result[:success]
    output = result[:output].to_s
    # `dokku help` lists plugin summaries on 0.38, while `help --all` (and older
    # releases) list fully-qualified commands. Accept both shapes without
    # depending on a particular Dokku release's help formatting.
    command_namespaces = output.scan(/\b([a-z][a-z0-9-]*):[a-z][a-z0-9-]*/).flatten
    plugin_namespaces = output.lines.filter_map { |line| line[/^\s{2,}([a-z][a-z0-9-]+)\s{2,}\S/, 1] }
    namespaces = (command_namespaces + plugin_namespaces).uniq.sort
    { version: @engine.server.dokku_version, namespaces: namespaces,
      features: %w[builds cron resource registry logs maintenance].index_with { |name| namespaces.include?(name) } }
  end
end
