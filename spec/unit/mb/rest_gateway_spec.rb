require 'spec_helper'

describe MB::RestGateway do
  include Rack::Test::Methods

  after { subject.terminate }

  describe "#app" do
    it "returns MB::API::Application" do
      subject.app.should be_a(MB::API::Application)
    end
  end
end
