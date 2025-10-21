# AI Provider Settings Module
# These settings will be used to create our circuits

module AIProviderSettings
  # If 3 consecutive failures occur, trip the circuit
  CIRCUIT_THRESHOLD  = 3

  # Stay open for 30 minutes before moving to Half-Open
  # Using 30 seconds for testing, change to 1800 for production
  FAILURE_COOLDOWN_S = 30 # 30 seconds for testing (use 1800 for production)

  # Only these errors will count as "failures"
  # These cover common API errors from OpenAI and Gemini (if their libs are loaded)
  # We guard references so they don't raise NameError if Faraday/RubyLLM aren't loaded yet.
  _tracked = []
  _tracked << RubyLLM::Error if defined?(RubyLLM::Error)
  _tracked << Faraday::Error if defined?(Faraday::Error)
  _tracked << Faraday::TimeoutError if defined?(Faraday::TimeoutError)
  _tracked << Faraday::ConnectionFailed if defined?(Faraday::ConnectionFailed)
  _tracked << Timeout::Error if defined?(Timeout::Error)
  _tracked << Net::ReadTimeout if defined?(Net::ReadTimeout)
  _tracked << Net::OpenTimeout if defined?(Net::OpenTimeout)
  _tracked << StandardError # Catch-all for other errors
  TRACKING_ERRORS = _tracked.freeze
end
