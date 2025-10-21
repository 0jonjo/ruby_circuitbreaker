#!/usr/bin/env ruby
# Resilient AI Client using RubyLLM with Stoplight-based circuit breaker and failover

require 'logger'
require_relative 'stoplight_config'
require_relative 'ai_provider_settings'
require_relative 'ruby_llm_config'

# Our priority list for failover (adjust as desired)
# Using widely-available model IDs to avoid "Unknown model" warnings.
MODEL_PRIORITY = ['gpt-4o', 'gemini-2.5-flash', 'gpt-4o-mini']

# The main failover method using RubyLLM chat object
# Contract:
# - Input: chat_object (RubyLLM::Chat), new_prompt (String)
# - Output: RubyLLM response object (responds to .content and .model_id)
# - Errors: raises StandardError when all models fail
# - Success: returns first successful response, preserving chat history across model switches

def ask_with_failover(chat_object, new_prompt)
  last_error = nil

  MODEL_PRIORITY.each do |model_name|
    light_name = "ai_models:#{model_name}"

    begin
      light = Stoplight(light_name,
                threshold:      AIProviderSettings::CIRCUIT_THRESHOLD,
                cool_off_time:  AIProviderSettings::FAILURE_COOLDOWN_S,
                tracked_errors: AIProviderSettings::TRACKING_ERRORS,
                data_store:     ($STOPLIGHT_DATA_STORE || Stoplight::DataStore::Memory.new)
              )

      return light.run do
        chat_object.with_model(model_name)
        response = chat_object.ask(new_prompt)
        puts "[AI SUCCESS] ✅ #{model_name} responded"
        response
      end

    rescue Stoplight::Error::RedLight => e
      puts "[AI FAILOVER] 🔴 Circuit open for #{model_name}"
      last_error = e
      next
    rescue *AIProviderSettings::TRACKING_ERRORS => e
      puts "[AI FAILOVER] ❌ #{model_name} failed: #{e.message}"
      last_error = e
      next
    end
  end

  raise StandardError, "All AI models failed. Last error: #{last_error&.message}"
end
