require "rails_helper"

RSpec.describe ApiToken, type: :model do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, owner: user) }
  let!(:membership) { create(:organization_membership, user: user, organization: organization, role: :owner) }
  let(:project) { create(:project, organization: organization) }

  def issue(**overrides)
    described_class.issue!(organization: organization, user: user, name: "CI agent", scopes: [ "read" ], **overrides)
  end

  it "returns the secret once and stores only its digest" do
    token = issue

    expect(token.plaintext).to start_with(ApiToken::PREFIX)
    expect(token.prefix).to eq(token.plaintext.delete_prefix(ApiToken::PREFIX).first(ApiToken::PREFIX_LENGTH))
    expect(token.token_digest).to eq(ApiToken.digest(token.plaintext))
    expect(token.token_digest).not_to eq(token.plaintext)
    expect(ApiToken.authenticate(token.plaintext)).to eq(token)
  end

  it "does not authenticate a wrong, truncated or foreign secret" do
    token = issue

    expect(ApiToken.authenticate("#{token.plaintext}x")).to be_nil
    expect(ApiToken.authenticate(token.plaintext[0..-2])).to be_nil
    expect(ApiToken.authenticate("not-a-token")).to be_nil
  end

  it "always carries read alongside a write scope" do
    token = issue(scopes: [ "deploy" ])

    expect(token.scopes).to contain_exactly("read", "deploy")
  end

  it "rejects unknown scopes" do
    expect { issue(scopes: [ "root" ]) }.to raise_error(ActiveRecord::RecordInvalid, /unknown scopes/)
  end

  it "rejects an empty scope list" do
    expect { issue(scopes: []) }.to raise_error(ActiveRecord::RecordInvalid, /at least one scope/)
  end

  it "derives the project from a bound environment" do
    environment = project.environments.create!(name: "staging", slug: "staging")

    token = issue(environment_id: environment.id)

    expect(token.project_id).to eq(project.id)
  end

  it "refuses an environment that belongs to another project" do
    other = create(:project, organization: organization)
    environment = other.environments.create!(name: "staging", slug: "staging")

    expect { issue(project_id: project.id, environment_id: environment.id) }
      .to raise_error(ActiveRecord::RecordInvalid, /does not belong to the project/)
  end

  it "refuses a project from another organization" do
    other = create(:organization)

    expect { issue(project_id: create(:project, organization: other).id) }
      .to raise_error(ActiveRecord::RecordInvalid, /must belong to the organization/)
  end

  it "reports expiry and revocation separately" do
    token = issue(expires_at: 1.hour.from_now)
    expect(token).to be_active

    token.update!(expires_at: 1.minute.ago)
    expect(token).to be_expired
    expect(token).not_to be_active

    token.update!(expires_at: nil)
    token.revoke!
    expect(token).to be_revoked
    expect(token).not_to be_active
  end

  it "refuses an unparseable expiry instead of treating it as none" do
    expect { issue(expires_at: "not-a-time") }.to raise_error(ArgumentError, /not a valid time/)
  end

  it "throttles last_used_at writes" do
    token = issue

    expect { token.touch_last_used! }.to change { token.reload.last_used_at }
    expect { token.touch_last_used! }.not_to change { token.reload.last_used_at }
  end
end
