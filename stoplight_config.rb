#!/usr/bin/env ruby
# Stoplight configuration (memory-only; no Redis)

require 'stoplight'

# Configure Stoplight once for the app
Stoplight.configure do |config|
  # Silence external notifiers
  config.error_notifier = ->(_) {}
  config.notifiers      = []

  # Always use in-memory data store for this project (no Redis)
  memory_store = Stoplight::DataStore::Memory.new
  config.data_store = memory_store

  # Make it accessible for scripts that pass data_store explicitly
  $STOPLIGHT_DATA_STORE = memory_store
end

puts "✅ Stoplight configured with #{$STOPLIGHT_DATA_STORE.class.name}" if defined?($STOPLIGHT_DATA_STORE)
