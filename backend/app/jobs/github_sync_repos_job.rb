class GithubSyncReposJob < ApplicationJob
  queue_as :default

  def perform(git_source_id)
    git_source = GitSource.find_by(id: git_source_id)
    return unless git_source&.installation_id.present?

    repos = GithubAppService.list_repos(git_source.installation_id)
    git_source.update!(metadata: (git_source.metadata || {}).merge('repos' => repos))
  rescue => e
    Rails.logger.error "GithubSyncReposJob failed for GitSource #{git_source_id}: #{e.message}"
  end
end
