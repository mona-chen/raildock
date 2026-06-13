require 'rails_helper'

RSpec.describe ChangeClassifier do
  describe '.classify' do
    it 'classifies reload fields' do
      %i[env domains storage proxy traefik_labels letsencrypt maintenance_mode].each do |field|
        expect(described_class.classify(field)).to eq(:reload)
      end
    end

    it 'classifies restart fields' do
      %i[limits reservations checks cron scaling restart_policy restart_max_retries auto_deploy depends_on].each do |field|
        expect(described_class.classify(field)).to eq(:restart)
      end
    end

    it 'classifies redeploy fields' do
      %i[builder docker_image git_repo branch source root_directory start_command exposed port version subtype category].each do |field|
        expect(described_class.classify(field)).to eq(:redeploy)
      end
    end
  end

  describe '.aggregate' do
    it 'returns reload for reload-only changes' do
      changes = [ { field: :env }, { field: :domains } ]
      expect(described_class.aggregate(changes)).to eq(:reload)
    end

    it 'returns restart when restart is present' do
      changes = [ { field: :env }, { field: :scaling } ]
      expect(described_class.aggregate(changes)).to eq(:restart)
    end

    it 'returns redeploy when redeploy is present' do
      changes = [ { field: :env }, { field: :builder } ]
      expect(described_class.aggregate(changes)).to eq(:redeploy)
    end
  end
end
