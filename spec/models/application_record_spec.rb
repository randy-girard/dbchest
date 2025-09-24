require 'rails_helper'

RSpec.describe ApplicationRecord, type: :model do
  describe "base configuration" do
    it "inherits from ActiveRecord::Base" do
      expect(ApplicationRecord).to be < ActiveRecord::Base
    end

    it "is abstract class" do
      expect(ApplicationRecord.abstract_class).to be true
    end
  end
end
