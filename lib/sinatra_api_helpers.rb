
# Convenience methods which assist in building JSON-based APIs. Mix these into any instance of Sinatra::Base.
module SinatraApiHelpers
  MAX_JSON_REQUEST_BODY_SIZE = 1024 * 100 # 100K

  attr_accessor :json_body

  # Renders a 400 if any of the specified parameters are missing from the request's body.
  def enforce_required_json_keys(*required_keys)
    missing = Array(required_keys).select { |param| [nil, ""].include?(json_body[param.to_sym]) }
    unless missing.empty?
      show_error(400, "These keys are missing from the JSON body: " + missing.join(", ") + ".")
    end
  end

  # Parses the request body as JSON and builds a symbolized hash.
  def json_body
    if @json_body.nil?
      body = enforce_valid_json_body
      @json_body ||= SinatraApiHelpers.symbolize_hash_keys(body)
    end
    @json_body
  end

  def request_body
    # Save the request body as a string
    @request_body ||= request.body.read
  end

  def show_error(status_code, message) halt(status_code, { :message => message }.to_json) end

  def enforce_valid_json_body
    # Cap the size of the JSON request body; parsing a huge request will make our memory usage soar.
    # TODO(philc): We may want to log this. It's a strange occurence.
    if request.env["CONTENT_LENGTH"].to_i > MAX_JSON_REQUEST_BODY_SIZE
      show_error 400, "Your JSON request body is too large."
    end
    if request_body.blank?
      show_error 400, "This URL requires a request body in JSON format. Your request's body is blank."
    end
    json_body = JSON.parse(self.request_body) rescue nil
    show_error 400, "Invalid JSON in the request body." if json_body.nil?
    json_body
  end

  def self.symbolize_hash_keys(body)
    if body.is_a?(Array)
      return body.map { |sub_body| symbolize_hash_keys(sub_body) }
    elsif body.is_a?(Hash)
      new_body = {}
      body.each { |key, value| new_body[key.to_sym] = symbolize_hash_keys(value) }
    else
      return body
    end
    new_body
  end
end