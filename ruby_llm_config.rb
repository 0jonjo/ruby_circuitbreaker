# RubyLLM configuration for unified LLM access
# Loads environment variables and configures provider API keys

require 'dotenv/load'
require 'ruby_llm'

RubyLLM.configure do |config|
  # Set provider API keys via ENV
  config.openai_api_key = ENV['OPENAI_API_KEY'] if ENV['OPENAI_API_KEY']
  config.gemini_api_key = ENV['GEMINI_API_KEY'] if ENV['GEMINI_API_KEY']
  # You can add other providers here (e.g., Anthropic)
end

# Small sanity message to help during local runs
begin
  providers = []
  providers << 'OpenAI' if ENV['OPENAI_API_KEY']
  providers << 'Gemini' if ENV['GEMINI_API_KEY']
  puts "✅ RubyLLM configured (providers: #{providers.any? ? providers.join(', ') : 'none'})"
rescue => e
  warn "⚠️  RubyLLM configuration check failed: #{e.message}"
end
