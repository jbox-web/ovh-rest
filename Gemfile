# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

# Dev libs
# irb is only needed for bin/console; scope it to MRI so it does not drag rdoc
# -> rbs (a native extension that fails to build on JRuby) into the bundle.
gem 'irb', platforms: :mri
gem 'rake'
gem 'rspec'
gem 'simplecov'

# Dev tools / linter
gem 'guard-rspec',         require: false
gem 'rubocop',             require: false
gem 'rubocop-performance', require: false
gem 'rubocop-rake',        require: false
gem 'rubocop-rspec',       require: false
gem 'yard',                require: false
