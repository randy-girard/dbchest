require 'rails_helper'

RSpec.describe ApplicationMailer, type: :mailer do
  describe "default configuration" do
    it "has default from address" do
      expect(ApplicationMailer.default[:from]).to be_present
    end

    it "inherits from ActionMailer::Base" do
      expect(ApplicationMailer).to be < ActionMailer::Base
    end
  end
end
