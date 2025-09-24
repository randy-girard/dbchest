require 'rails_helper'

RSpec.describe ApplicationJob, type: :job do
  describe "configuration" do
    it "inherits from ActiveJob::Base" do
      expect(ApplicationJob).to be < ActiveJob::Base
    end

    it "has queue adapter configured" do
      expect(ApplicationJob.queue_adapter).to be_present
    end
  end
end
