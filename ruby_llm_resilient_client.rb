#!/usr/bin/env ruby
# Resilient AI Client using RubyLLM with Stoplight-based circuit breaker and failover

require 'logger'
require_relative 'stoplight_config'
require_relative 'ai_provider_settings'
require_relative 'ruby_llm_config'

# Our priority list for failover (adjust as desired)
# Using widely-available model IDs to avoid "Unknown model" warnings.
MODEL_PRIORITY = ['gpt-4o', 'gemini-2.5-flash', 'gpt-4o-mini']

# Mock logger for standalone testing
module Rails
  def self.logger
    @logger ||= Logger.new(STDOUT)
  end
end

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
        Rails.logger.info "[AI SUCCESS] ✅ #{model_name} responded"
        response
      end

    rescue Stoplight::Error::RedLight => e
      Rails.logger.warn "[AI FAILOVER] 🔴 Circuit open for #{model_name}"
      last_error = e
      next
    rescue *AIProviderSettings::TRACKING_ERRORS => e
      Rails.logger.warn "[AI FAILOVER] ❌ #{model_name} failed: #{e.message}"
      last_error = e
      next
    end
  end

  raise StandardError, "All AI models failed. Last error: #{last_error&.message}"
end

# Helper method to get circuit status

def get_circuit_status(model_name)
  light_name = "ai_models:#{model_name}"
  light = Stoplight(light_name,
                    threshold:      AIProviderSettings::CIRCUIT_THRESHOLD,
                    cool_off_time:  AIProviderSettings::FAILURE_COOLDOWN_S,
                    tracked_errors: AIProviderSettings::TRACKING_ERRORS,
                    data_store:     ($STOPLIGHT_DATA_STORE || Stoplight::DataStore::Memory.new))
  state = case light.color
          when Stoplight::Color::RED then 'open'
          when Stoplight::Color::YELLOW then 'half_open'
          else 'closed'
          end

  {
    model: model_name,
    state: state,
    failures: nil
  }
end

# Display all circuit statuses

def display_all_circuits
  puts "\n" + "="*70
  puts "Circuit Breaker Status"
  puts "="*70

  MODEL_PRIORITY.each do |model|
    status = get_circuit_status(model)
    state_icon = case status[:state]
                 when 'open' then '🔴'
                 when 'half_open' then '🟡'
                 else '🟢'
                 end

    failures_text = status[:failures].nil? ? 'N/A' : status[:failures].to_s
    puts "#{state_icon} #{status[:model].ljust(30)} | State: #{status[:state].ljust(10)} | Failures: #{failures_text}"
  end
  puts "="*70 + "\n"
end

if __FILE__ == $PROGRAM_NAME
  require 'ruby_llm'
  puts "🚀 Testing RubyLLM Resilient Client with Circuit Breaker"
  puts "="*70

  # Quick key presence check (RubyLLM can still work with one provider)
  if !ENV['OPENAI_API_KEY'] && !ENV['GEMINI_API_KEY']
    warn "❌ No API keys found. Set OPENAI_API_KEY and/or GEMINI_API_KEY in .env"
    exit 1
  end

  chat = RubyLLM.chat # Create a chat session; model will be set per attempt

  puts "\n📝 Scenario 1: Normal operation with real APIs"
  puts "-"*70

  display_all_circuits

  begin
    response = ask_with_failover(chat, "What is the Circuit Breaker pattern in one sentence?")
    puts "\n✅ Response received!"
    puts "Model: #{response.model_id}"
    puts "Content: #{response.content}\n"
  rescue => e
    puts "❌ Error: #{e.message}"
  end

  display_all_circuits

  puts "\n📝 Scenario 2: Follow-up question (preserving context)"
  puts "-"*70

  begin
    response = ask_with_failover(chat, "Give me an example use case.")
    puts "\n✅ Response received!"
    puts "Model: #{response.model_id}"
    puts "Content: #{response.content}\n"
  rescue => e
    puts "❌ Error: #{e.message}"
  end

  display_all_circuits

  puts "\n🎉 Test complete!"
  puts "Chat history preserved with #{chat.messages.size} messages" if chat.respond_to?(:messages)
end
