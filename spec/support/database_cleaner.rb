RSpec.configure do |config|
  config.before(:suite) do
    # Ensure we're only working with the test database
    if Rails.env.test?
      DatabaseCleaner.strategy = :transaction
      DatabaseCleaner.clean_with(:truncation)
    else
      raise "DatabaseCleaner should only run in test environment!"
    end
  end

  config.around(:each) do |example|
    if Rails.env.test?
      DatabaseCleaner.cleaning do
        example.run
      end
    else
      raise "Tests should only run in test environment!"
    end
  end
end
