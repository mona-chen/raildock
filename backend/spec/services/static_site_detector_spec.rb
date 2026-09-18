require "rails_helper"

RSpec.describe StaticSiteDetector do
  def detect(package_json, files: {})
    described_class.detect(package_json: package_json, files: files)
  end

  it "detects a Vite app and its default output directory" do
    result = detect(
      {
        "scripts" => { "dev" => "vite", "build" => "tsc && vite build" },
        "dependencies" => { "react" => "^19.0.0" },
        "devDependencies" => { "vite" => "^6.0.0" }
      }
    )

    expect(result.framework).to eq("vite")
    expect(result.publish_directory).to eq("dist")
    expect(result.spa_fallback).to be(true)
  end

  it "reads a custom Vite outDir" do
    result = detect(
      {
        "scripts" => { "build" => "vite build" },
        "devDependencies" => { "vite" => "^6.0.0" }
      },
      files: { "vite.config.ts" => "export default { build: { outDir: 'build/www' } }" }
    )

    expect(result.publish_directory).to eq("build/www")
  end

  it "detects Create React App" do
    result = detect(
      {
        "scripts" => { "start" => "react-scripts start", "build" => "react-scripts build" },
        "dependencies" => { "react-scripts" => "5.0.1" }
      }
    )

    expect(result.framework).to eq("cra")
    expect(result.publish_directory).to eq("build")
  end

  it "detects Angular and its browser output directory" do
    angular_json = JSON.generate(
      "projects" => {
        "my-app" => {
          "architect" => {
            "build" => {
              "builder" => "@angular-devkit/build-angular:application",
              "options" => { "outputPath" => "dist/my-app" }
            }
          }
        }
      }
    )

    result = detect(
      {
        "scripts" => { "ng" => "ng", "start" => "ng serve", "build" => "ng build" },
        "dependencies" => { "@angular/core" => "^19.0.0" }
      },
      files: { "angular.json" => angular_json }
    )

    expect(result.framework).to eq("angular")
    expect(result.publish_directory).to eq("dist/my-app/browser")
  end

  it "detects Gatsby" do
    result = detect(
      {
        "scripts" => { "build" => "gatsby build" },
        "dependencies" => { "gatsby" => "^5.0.0" }
      }
    )

    expect(result.framework).to eq("gatsby")
    expect(result.publish_directory).to eq("public")
  end

  it "detects a Next static export" do
    result = detect(
      {
        "scripts" => { "build" => "next build" },
        "dependencies" => { "next" => "^15.0.0" }
      },
      files: { "next.config.mjs" => "export default { output: 'export' }" }
    )

    expect(result.framework).to eq("next")
    expect(result.publish_directory).to eq("out")
  end

  it "ignores Next without a static export" do
    result = detect(
      {
        "scripts" => { "build" => "next build" },
        "dependencies" => { "next" => "^15.0.0" }
      }
    )

    expect(result).to be_nil
  end

  it "ignores apps with a custom start command (a real server)" do
    result = detect(
      {
        "scripts" => { "start" => "node server.js", "build" => "vite build" },
        "devDependencies" => { "vite" => "^6.0.0" }
      }
    )

    expect(result).to be_nil
  end

  it "still detects a Vite app whose start script only previews the build" do
    result = detect(
      {
        "scripts" => { "start" => "vite preview", "build" => "vite build" },
        "devDependencies" => { "vite" => "^6.0.0" }
      }
    )

    expect(result.framework).to eq("vite")
    expect(result.publish_directory).to eq("dist")
  end

  it "ignores SvelteKit without a static adapter" do
    result = detect(
      {
        "scripts" => { "build" => "vite build" },
        "devDependencies" => { "vite" => "^6.0.0", "@sveltejs/kit" => "^2.0.0" }
      }
    )

    expect(result).to be_nil
  end

  it "extracts the Node major version from engines" do
    result = detect(
      {
        "scripts" => { "build" => "vite build" },
        "devDependencies" => { "vite" => "^6.0.0" },
        "engines" => { "node" => ">=20.11.0" }
      }
    )

    expect(result.node_version).to eq("20")
  end
end
