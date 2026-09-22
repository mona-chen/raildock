require 'rails_helper'

RSpec.describe ManifestSchema do
  describe '.validate' do
    context 'valid raildock manifest' do
      let(:hash) do
        {
          "services" => [
            { "name" => "web", "category" => "app", "subtype" => "web" }
          ]
        }
      end

      it 'returns success' do
        result = described_class.validate(hash)
        expect(result.success?).to be true
        expect(result.errors).to be_empty
      end
    end

    context 'missing services' do
      it 'returns error' do
        result = described_class.validate({})
        expect(result.success?).to be false
        expect(result.errors).to include("raildock: 'services' must be an array")
      end
    end

    context 'invalid category' do
      let(:hash) do
        {
          "services" => [
            { "name" => "web", "category" => "invalid", "subtype" => "web" }
          ]
        }
      end

      it 'returns category error' do
        result = described_class.validate(hash)
        expect(result.success?).to be false
        expect(result.errors).to include(a_string_matching(/category/))
      end
    end

    context 'invalid subtype' do
      let(:hash) do
        {
          "services" => [
            { "name" => "myapp", "category" => "app", "subtype" => "rails" }
          ]
        }
      end

      it 'returns subtype error' do
        result = described_class.validate(hash)
        expect(result.success?).to be false
        expect(result.errors).to include(a_string_matching(/subtype.*rails.*not registered/))
      end
    end

    context 'valid database subtype' do
      let(:hash) do
        {
          "services" => [
            { "name" => "db", "category" => "database", "subtype" => "postgres" }
          ]
        }
      end

      it 'returns success' do
        result = described_class.validate(hash)
        expect(result.success?).to be true
      end
    end

    context 'valid static site settings' do
      let(:hash) do
        {
          "services" => [
            {
              "name" => "web", "category" => "app", "subtype" => "web",
              "publish_directory" => "dist", "spa_fallback" => true, "node_version" => "22"
            }
          ]
        }
      end

      it 'returns success' do
        expect(described_class.validate(hash).success?).to be true
      end
    end

    context 'invalid static site settings' do
      it 'rejects a non-boolean spa_fallback' do
        result = described_class.validate(
          "services" => [ { "name" => "web", "subtype" => "web", "spa_fallback" => "yes" } ]
        )

        expect(result.success?).to be false
        expect(result.errors).to include(a_string_matching(/spa_fallback.*boolean/))
      end

      it 'rejects a non-boolean plain_static' do
        result = described_class.validate(
          "services" => [ { "name" => "web", "category" => "app", "subtype" => "web", "plain_static" => "yes" } ]
        )

        expect(result.success?).to be false
        expect(result.errors).to include(a_string_matching(/plain_static.*boolean/))
      end
    end

    context 'plain static site settings' do
      it 'accepts a boolean plain_static' do
        result = described_class.validate(
          "services" => [
            { "name" => "web", "category" => "app", "subtype" => "web", "plain_static" => true }
          ]
        )

        expect(result.success?).to be true
      end

    context 'nil static site settings' do
      # RepositoryDiscovery serializes a normalized service hash to JSON, which
      # turns unset optional fields into explicit null. Import validation must
      # treat those as absent rather than a type error.
      it 'treats nil as unset' do
        result = described_class.validate(
          "services" => [
            {
              "name" => "web", "category" => "app", "subtype" => "web",
              "publish_directory" => nil, "spa_fallback" => nil, "node_version" => nil
            }
          ]
        )

        expect(result.success?).to be true
      end
    end

    context 'valid app.json' do
      let(:hash) do
        {
          "name" => "my-app",
          "buildpacks" => [ "heroku/ruby" ],
          "formation" => { "web" => { "quantity" => 1 } }
        }
      end

      it 'returns success' do
        result = described_class.validate(hash)
        expect(result.success?).to be true
      end
    end
  end
end
