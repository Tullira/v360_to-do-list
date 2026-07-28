require "rails_helper"

RSpec.describe "Permissions-Policy", type: :request do
  it "nega os recursos que a aplicacao nao usa" do
    get login_path

    policy = response.headers["Permissions-Policy"]

    expect(policy).to be_present
    %w[camera microphone geolocation payment usb].each do |recurso|
      expect(policy).to include("#{recurso}=()")
    end
  end
end
