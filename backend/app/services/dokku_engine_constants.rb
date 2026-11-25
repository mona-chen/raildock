# SSH connection configuration constants
module DokkuEngineConstants
  SSH_TIMEOUT = 30
  SSH_CONNECTION_TIMEOUT = 10
  SSH_USER = "dokku"

  # Regex patterns for parsing Dokku output
  DOKKU_VERSION_REGEX = /dokku version (\S+)/
  DOCKER_VERSION_REGEX = /Docker version ([\d\.]+)/
  DOKKU_APPS_LOCKED_REGEX = /Deploy lock exists|locked/i
end
