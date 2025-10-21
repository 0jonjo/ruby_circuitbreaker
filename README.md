# CIRCUIT BREAKER WITH RUBYLLM + STOPLIGHT

## Quick start

1) Install deps

```bash
bundle install
```

2) Create .env

```bash
cp .env.example .env
# then edit .env and set at least one key
# OPENAI_API_KEY=...
# GEMINI_API_KEY=...
```

3) Smoke test (one liner)

```bash
ruby -e "require_relative 'ruby_llm_resilient_client'; require 'ruby_llm'; chat = RubyLLM.chat; r = ask_with_failover(chat, 'Say hello in five words.'); puts 'Model: ' + r.model_id; puts r.content"
```

4) Interactive test with IRB

```bash
irb -r ./ruby_llm_resilient_client.rb -r ruby_llm
```

Then inside IRB:

```ruby
chat = RubyLLM.chat
r = ask_with_failover(chat, "What is the Circuit Breaker pattern in one sentence?")
puts r.model_id
puts r.content

# Follow-up (preserves context)
r2 = ask_with_failover(chat, "Give me an example use case.")
puts r2.content
```

Exit IRB with `exit` or `Ctrl+D`.

## What's inside

- `ruby_llm_resilient_client.rb` — failover logic using RubyLLM + Stoplight
- `stoplight_config.rb` — Stoplight v5 config (memory-only datastore)
- `ai_provider_settings.rb` — thresholds and tracked errors
- `ruby_llm_config.rb` — RubyLLM keys from ENV

## Model priority

Use realistic, available model IDs to avoid unknown-model errors. Default priority in this repo favors widely available models:

```ruby
MODEL_PRIORITY = ['gpt-4o', 'gemini-2.5-flash', 'gpt-4o-mini']
```

You can reorder to prefer Gemini first:

```ruby
MODEL_PRIORITY = ['gemini-2.5-flash', 'gpt-4o', 'gpt-4o-mini']
```

## How it works

- We configure Stoplight with a memory datastore (no Redis).
- For each model, we create a circuit breaker with:
  - `threshold`: number of failures to trip the circuit
  - `cool_off_time`: time window before a recovery probe
  - `tracked_errors`: errors that count as failures (e.g., `RubyLLM::Error`)
- The chat call loops through `MODEL_PRIORITY` and returns the first success.
- Circuit status uses `light.color` (Stoplight v5 public API):
  - GREEN = closed
  - YELLOW = half open
  - RED = open

## Configuration snippets

### Stoplight (v5) memory-only

```ruby
# stoplight_config.rb
require 'stoplight'

Stoplight.configure do |config|
  config.error_notifier = ->(_) {}
  config.notifiers      = []

  memory_store = Stoplight::DataStore::Memory.new
  config.data_store = memory_store
  $STOPLIGHT_DATA_STORE = memory_store
end
```

### RubyLLM

```ruby
# ruby_llm_config.rb
require 'dotenv/load'
require 'ruby_llm'

RubyLLM.configure do |config|
  config.openai_api_key = ENV['OPENAI_API_KEY'] if ENV['OPENAI_API_KEY']
  config.gemini_api_key = ENV['GEMINI_API_KEY'] if ENV['GEMINI_API_KEY']
end
```

### Circuit settings

```ruby
# ai_provider_settings.rb
module AIProviderSettings
  CIRCUIT_THRESHOLD  = 3
  FAILURE_COOLDOWN_S = 30
  TRACKING_ERRORS = [RubyLLM::Error, StandardError]
end
```

### Failover helper

```ruby
# excerpt from ruby_llm_resilient_client.rb
def ask_with_failover(chat, prompt)
  last_error = nil
  MODEL_PRIORITY.each do |model_name|
    light = Stoplight("ai_models:#{model_name}",
      threshold:      AIProviderSettings::CIRCUIT_THRESHOLD,
      cool_off_time:  AIProviderSettings::FAILURE_COOLDOWN_S,
      tracked_errors: AIProviderSettings::TRACKING_ERRORS,
      data_store:     ($STOPLIGHT_DATA_STORE || Stoplight::DataStore::Memory.new)
    )

    begin
      return light.run do
        chat.with_model(model_name)
        chat.ask(prompt)
      end
    rescue Stoplight::Error::RedLight, *AIProviderSettings::TRACKING_ERRORS => e
      last_error = e
      next
    end
  end
  raise StandardError, "All AI models failed. Last error: #{last_error&.message}"
end
```

## Troubleshooting

- "Unknown model" — switch to `gpt-4o` / `gemini-2.5-flash` / `gpt-4o-mini` or reorder priority.
- "No API keys found" — create `.env` and set at least one key.
- Circuit remains RED — wait `FAILURE_COOLDOWN_S` seconds for half-open or adjust threshold.

## Notes

- This project intentionally uses Stoplight’s in-memory store (no Redis) for simplicity.
- For production, you may switch to Redis data store, add observability, retries, and cost controls.

## License

MIT
