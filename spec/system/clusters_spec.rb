require 'rails_helper'

RSpec.describe "Clusters", type: :system do
  let(:cluster) { create(:cluster) }

  describe "visiting the index" do
    it "displays the clusters page" do
      visit clusters_path
      expect(page).to have_selector("h1", text: "Clusters")
    end
  end

  describe "creating a cluster" do
    it "allows user to create a new cluster" do
      visit clusters_path
      click_on "New cluster"

      fill_in "Name", with: "Test Cluster"
      click_on "Create Cluster"

      expect(page).to have_text("Cluster was successfully created")
      click_on "Back"
    end
  end

  describe "updating a cluster" do
    it "allows user to update an existing cluster" do
      visit cluster_path(cluster)
      click_on "Edit this cluster", match: :first

      fill_in "Name", with: "Updated Cluster"
      click_on "Update Cluster"

      expect(page).to have_text("Cluster was successfully updated")
      click_on "Back"
    end
  end

  describe "destroying a cluster" do
    it "allows user to destroy a cluster" do
      visit cluster_path(cluster)
      click_on "Destroy this cluster", match: :first

      expect(page).to have_text("Cluster was successfully destroyed")
    end
  end
end
