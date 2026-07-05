require 'rails_helper'

RSpec.describe ConfigSchema do
  let(:schema) do
    {
      "endpoint" => { type: "string", required: true, label: "Endpoint" },
      "count" => { type: "integer", required: false, label: "Count", min: 0, max: 10 },
      "enabled" => { type: "boolean", required: true, label: "Enabled" },
      "region" => { type: "select", required: false, label: "Region", options: ["us", "eu"] }
    }
  end

  it "returns no errors for valid values" do
    errors = ConfigSchema.validate({ "endpoint" => "https://a.com", "enabled" => true, "count" => 5 }, schema)
    expect(errors).to be_empty
  end

  it "reports missing required fields" do
    errors = ConfigSchema.validate({ "enabled" => true }, schema)
    expect(errors).to include(/Endpoint is required/)
  end

  it "rejects empty strings for required fields" do
    errors = ConfigSchema.validate({ "endpoint" => "", "enabled" => true }, schema)
    expect(errors).to include(/Endpoint is required/)
  end

  it "validates integer type and range" do
    errors = ConfigSchema.validate({ "endpoint" => "x", "enabled" => true, "count" => "abc" }, schema)
    expect(errors).to include(/Count must be an integer/)

    errors = ConfigSchema.validate({ "endpoint" => "x", "enabled" => true, "count" => 11 }, schema)
    expect(errors).to include(/Count must be at most 10/)
  end

  it "coerces string numbers from params" do
    errors = ConfigSchema.validate({ "endpoint" => "x", "enabled" => true, "count" => "5" }, schema)
    expect(errors).not_to include(/Count must be an integer/)
  end

  it "validates select options" do
    errors = ConfigSchema.validate({ "endpoint" => "x", "enabled" => true, "region" => "ap" }, schema)
    expect(errors).to include(/Region must be one of us, eu/)
  end

  it "validates booleans from string params" do
    errors = ConfigSchema.validate({ "endpoint" => "x", "enabled" => "true" }, schema)
    expect(errors).to be_empty

    errors = ConfigSchema.validate({ "endpoint" => "x", "enabled" => "maybe" }, schema)
    expect(errors).to include(/Enabled must be a boolean/)
  end
end
