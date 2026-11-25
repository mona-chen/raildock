require "rails_helper"
require "tempfile"
require "open3"

RSpec.describe AppFileBrowser do
  let(:service) { create(:service) }
  let(:host) { double("HostEngine") }
  let(:browser) { described_class.new(service, process_type: "web", host: host) }

  before do
    create(:process_type, service: service, name: "web", quantity: 1)
    allow(host).to receive(:with_session).and_yield
    allow(host).to receive(:dokku_container_name)
      .with(service.dokku_app_name, process_type: "web")
      .and_return("#{service.dokku_app_name}.web.1")
  end

  it "lists NUL-delimited entries and returns the resolved working directory" do
    allow(host).to receive(:run)
      .with(a_string_including("docker exec", " sh /app"))
      .and_return(success: true, output: "/app\0d\t0\tlogs\0f\t12\tREADME.md\0")

    result = browser.list("/app")

    expect(result[:path]).to eq("/app")
    expect(result[:entries]).to contain_exactly(
      { type: "directory", name: "logs", size: 0 },
      { type: "file", name: "README.md", size: 12 }
    )
  end

  it "does not let a path escape by using parent segments" do
    expect(host).to receive(:run).with(a_string_including(" sh /app/etc")).and_return(success: true, output: "/app/etc\0")

    expect(browser.list("/app/../etc")[:path]).to eq("/app/etc")
  end

  it "exits successfully when a directory has fewer entries than the cap" do
    output, status = Open3.capture2e("sh", "-c", described_class::LIST_SCRIPT, "sh", Rails.root.to_s)

    expect(status).to be_success
    expect(output).to include("\0")
  end

  it "previews text and marks binary files without returning their bytes" do
    allow(host).to receive(:run).with(a_string_matching(/ sh \/app\/notes\.txt\z/))
      .and_return(success: true, output: "12\tHello world\n")
    text = browser.preview("/app/notes.txt")
    expect(text).to include(size: 12, binary: false, content: "Hello world\n")

    allow(host).to receive(:run).with(a_string_matching(/ sh \/app\/logo\.png\z/))
      .and_return(success: true, output: "4\ta\0b\0")
    binary = browser.preview("/app/logo.png")
    expect(binary).to include(binary: true, content: nil)
  end

  it "checks for an existing upload before writing through stdin" do
    Tempfile.create("raildock-upload") do |file|
      file.write("hello")
      file.flush

      allow(host).to receive(:run).with(a_string_matching(/ sh \/app\/notes\.txt\z/)).and_return(success: false)
      expect(host).to receive(:run_with_file)
        .with(a_string_matching(/docker exec -i .* sh -c .* sh \/app\/notes\.txt\z/), file.path)
        .and_return(success: true)

      expect(browser.write("/app", "notes.txt", file.path)).to include(path: "/app/notes.txt", name: "notes.txt", size: 5)
    end
  end

  it "refuses to overwrite an existing file unless asked" do
    Tempfile.create("raildock-upload") do |file|
      file.write("hello")
      file.flush
      allow(host).to receive(:run).with(a_string_matching(/ sh \/app\/notes\.txt\z/)).and_return(success: true)

      expect { browser.write("/app", "notes.txt", file.path) }
        .to raise_error(AppFileBrowser::Error) { |error| expect(error.status).to eq(:conflict) }
    end
  end
end
