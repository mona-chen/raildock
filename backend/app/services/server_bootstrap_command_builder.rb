class ServerBootstrapCommandBuilder
  def initialize(organization, base_url:)
    @organization = organization
    @base_url = base_url
  end

  def build
    key = organization.ensure_ssh_key!
    {
      public_key: key.public_key,
      command: command_for(key.public_key)
    }
  end

  private

  attr_reader :organization, :base_url

  def command_for(public_key)
    escaped_key = Shellwords.escape(public_key.strip)
    "curl -fsSL #{script_url} | bash -s -- #{escaped_key}"
  end

  def script_url
    "#{base_url.chomp('/')}/bootstrap.sh"
  end
end
