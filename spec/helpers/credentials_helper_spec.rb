require 'rails_helper'

RSpec.describe CredentialsHelper, type: :helper do
  # CredentialsHelper is currently empty, but we test that it exists and can be included
  describe 'module inclusion' do
    it 'can be included without errors' do
      expect { helper.class.include(CredentialsHelper) }.not_to raise_error
    end

    it 'is a module' do
      expect(CredentialsHelper).to be_a(Module)
    end

    it 'can be extended' do
      test_class = Class.new
      expect { test_class.extend(CredentialsHelper) }.not_to raise_error
    end
  end
end
