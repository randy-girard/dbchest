require 'rails_helper'

RSpec.describe "Clusters", type: :system do
  let!(:database_type) { create(:database_type, :with_versions) }
  let(:cluster) { create(:cluster, database_type: database_type) }

  describe "visiting the index" do
    it "displays the clusters page" do
      visit clusters_path
      expect(page).to have_selector("h2", text: "Clusters")
    end
  end

  describe "creating a cluster" do
    it "allows user to create a new cluster" do
      visit clusters_path
      click_on "New Cluster"

      fill_in "Name", with: "Test Cluster"
      select database_type.name, from: "Database Type"
      click_on "Create Cluster"

      expect(page).to have_text("Cluster was successfully created")
    end
  end

  describe "updating a cluster" do
    it "allows user to update an existing cluster" do
      visit cluster_path(cluster)
      click_on "Edit", match: :first

      fill_in "Name", with: "Updated Cluster"
      click_on "Update Cluster"

      expect(page).to have_text("Cluster was successfully updated")
    end
  end

  describe "destroying a cluster" do
    it "allows user to destroy a cluster" do
      visit cluster_path(cluster)
      click_on "Delete cluster", match: :first

      expect(page).to have_text("Cluster was successfully destroyed")
    end
  end
end
