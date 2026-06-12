require 'rails_helper'

RSpec.describe ManifestSchema do
  describe '.validate' do
    context 'valid raildock manifest' do
      let(:hash) do
        {
          "services" => [
            { "name" => "web", "category" => "app", "subtype" => "rails" }
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
            { "name" => "web", "category" => "invalid", "subtype" => "rails" }
          ]
        }
      end

      it 'returns category error' do
        result = described_class.validate(hash)
        expect(result.success?).to be false
        expect(result.errors).to include(a_string_matching(/category/))
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
