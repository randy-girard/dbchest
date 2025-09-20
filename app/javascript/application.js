// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Import ActionCable and make it available globally
import * as ActionCable from "@rails/actioncable"
window.ActionCable = ActionCable

// Also make createConsumer available globally for easier access
window.createConsumer = ActionCable.createConsumer

console.log("🚀 Application loaded - ActionCable available:", typeof ActionCable !== 'undefined')
