require 'rails_helper'

RSpec.describe ClustersHelper, type: :helper do
  # ClustersHelper is currently empty, but we test that it exists and can be included
  describe 'module inclusion' do
    it 'can be included without errors' do
      expect { helper.class.include(ClustersHelper) }.not_to raise_error
    end

    it 'is a module' do
      expect(ClustersHelper).to be_a(Module)
    end

    it 'can be extended' do
      test_class = Class.new
      expect { test_class.extend(ClustersHelper) }.not_to raise_error
    end
  end
end
