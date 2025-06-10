#!/usr/bin/env ruby

# Create synthetic Gemfiles based on patterns from real projects

require 'fileutils'

FileUtils.mkdir_p('synthetic_gemfiles')

# 1. Rails-like application
File.write('synthetic_gemfiles/rails_app_Gemfile', <<~GEMFILE)
  source 'https://rubygems.org'
  
  gem 'rails', '~> 7.0.0'
  gem 'pg', '>= 1.1'
  gem 'puma', '~> 6.0'
  gem 'redis', '~> 5.0'
  gem 'image_processing', '~> 1.2'
  
  # Frontend
  gem 'importmap-rails'
  gem 'turbo-rails'
  gem 'stimulus-rails'
  gem 'tailwindcss-rails'
  
  # Background jobs
  gem 'sidekiq', '~> 7.0'
  gem 'sidekiq-cron', '~> 1.10'
  
  group :development, :test do
    gem 'rspec-rails', '~> 6.0'
    gem 'factory_bot_rails'
    gem 'faker'
  end
  
  group :development do
    gem 'listen', '~> 3.3'
    gem 'spring'
  end
GEMFILE

# 2. API-only application
File.write('synthetic_gemfiles/api_app_Gemfile', <<~GEMFILE)
  source 'https://rubygems.org'
  
  gem 'rails', '~> 7.0.0'
  gem 'pg', '~> 1.1'
  gem 'puma', '~> 6.0'
  
  # API
  gem 'grape', '~> 1.8'
  gem 'grape-entity', '~> 1.0'
  gem 'rack-cors'
  
  # Serialization
  gem 'oj', '~> 3.16'
  gem 'fast_jsonapi'
  
  # Authentication
  gem 'jwt'
  gem 'bcrypt', '~> 3.1.7'
  
  # Monitoring
  gem 'sentry-ruby'
  gem 'sentry-rails'
GEMFILE

# 3. Sinatra microservice
File.write('synthetic_gemfiles/sinatra_Gemfile', <<~GEMFILE)
  source 'https://rubygems.org'
  
  gem 'sinatra', '~> 3.2'
  gem 'sinatra-contrib'
  gem 'puma', '~> 6.0'
  gem 'redis', '~> 5.0'
  gem 'connection_pool'
  
  gem 'rake'
  gem 'dotenv'
GEMFILE

# 4. Data processing app
File.write('synthetic_gemfiles/data_app_Gemfile', <<~GEMFILE)
  source 'https://rubygems.org'
  
  gem 'activerecord', '~> 7.0'
  gem 'pg', '~> 1.5'
  gem 'sidekiq', '~> 7.2'
  
  # Data processing
  gem 'nokogiri', '~> 1.15'
  gem 'httparty', '~> 0.21'
  gem 'csv'
  
  # AWS
  gem 'aws-sdk-s3', '~> 1.140'
  gem 'aws-sdk-sqs', '~> 1.70'
GEMFILE

# 5. E-commerce platform
File.write('synthetic_gemfiles/ecommerce_Gemfile', <<~GEMFILE)
  source 'https://rubygems.org'
  
  gem 'rails', '~> 7.0.0'
  gem 'pg', '~> 1.5'
  gem 'redis', '~> 5.0'
  
  # E-commerce
  gem 'money-rails', '~> 1.15'
  gem 'stripe', '~> 10.0'
  gem 'friendly_id', '~> 5.5'
  
  # Images
  gem 'image_processing', '~> 1.12'
  gem 'aws-sdk-s3', '~> 1.140'
  
  # Search
  gem 'pg_search', '~> 2.3'
  gem 'kaminari', '~> 1.2'
GEMFILE

# 6. Blog/CMS
File.write('synthetic_gemfiles/blog_Gemfile', <<~GEMFILE)
  source 'https://rubygems.org'
  
  gem 'rails', '~> 7.0.0'
  gem 'pg', '~> 1.5'
  gem 'puma', '~> 6.0'
  
  # CMS
  gem 'devise', '~> 4.9'
  gem 'cancancan', '~> 3.5'
  gem 'friendly_id', '~> 5.5'
  
  # Content
  gem 'redcarpet', '~> 3.6'
  gem 'rouge', '~> 4.2'
  gem 'image_processing', '~> 1.12'
GEMFILE

# 7. DevOps tools
File.write('synthetic_gemfiles/devops_Gemfile', <<~GEMFILE)
  source 'https://rubygems.org'
  
  gem 'rake', '~> 13.1'
  gem 'thor', '~> 1.3'
  
  # Infrastructure
  gem 'fog-aws', '~> 3.21'
  gem 'docker-api', '~> 2.2'
  
  # Monitoring
  gem 'prometheus-client', '~> 4.2'
  gem 'statsd-ruby', '~> 1.5'
GEMFILE

# 8. Testing framework
File.write('synthetic_gemfiles/testing_Gemfile', <<~GEMFILE)
  source 'https://rubygems.org'
  
  gem 'rspec', '~> 3.12'
  gem 'rspec-mocks', '~> 3.12'
  gem 'capybara', '~> 3.39'
  gem 'selenium-webdriver', '~> 4.16'
  
  gem 'factory_bot', '~> 6.4'
  gem 'faker', '~> 3.2'
  gem 'database_cleaner', '~> 2.0'
GEMFILE

# 9. Machine learning
File.write('synthetic_gemfiles/ml_app_Gemfile', <<~GEMFILE)
  source 'https://rubygems.org'
  
  gem 'rails', '~> 7.0'
  gem 'pg', '~> 1.5'
  
  # ML/Data Science
  gem 'numpy', '~> 0.4'
  gem 'matplotlib', '~> 1.0'
  gem 'scikit-learn', '~> 0.2'
  
  # Data processing
  gem 'daru', '~> 0.3'
  gem 'statsample', '~> 2.1'
GEMFILE

# 10. Minimal app
File.write('synthetic_gemfiles/minimal_Gemfile', <<~GEMFILE)
  source 'https://rubygems.org'
  
  gem 'rack', '~> 3.0'
  gem 'rackup', '~> 2.1'
  gem 'rake', '~> 13.0'
GEMFILE

puts "Created 10 synthetic Gemfiles in synthetic_gemfiles/"
puts "These represent common Ruby application patterns without gemspec dependencies"