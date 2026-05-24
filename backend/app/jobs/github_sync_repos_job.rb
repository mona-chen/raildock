class GithubSyncReposJob < ApplicationJob
  queue_as :default

  def perform(git_source_id)
    git_source = GitSource.find_by(id: git_source_id)
    return unless git_source&.installation_id.present?

    # Mark sync as in-progress
    git_source.update!(
      metadata: (git_source.metadata || {}).merge(
        'sync_started_at' => Time.now.iso8601,
        'sync_error' => nil
      )
    )

    repos = GithubAppService.list_repos(git_source.installation_id)

    git_source.update!(
      metadata: (git_source.metadata || {}).merge(
        'repos' => repos,
        'sync_completed_at' => Time.now.iso8601,
        'sync_error' => nil,
        'repo_count' => repos.length
      )
    )
  rescue => e
    Rails.logger.error "GithubSyncReposJob failed for GitSource #{git_source_id}: #{e.message}"
    git_source&.update!(
      metadata: (git_source.metadata || {}).merge(
        'sync_error' => e.message,
        'sync_failed_at' => Time.now.iso8601
      )
    )
  end
end
