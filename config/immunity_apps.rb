# For now, we're storing this configuration in a file.
# This is the first version of defining an apps's configuration, so it may evolve to a configuration DSL,
# or we may start performing this configuration through UI and storing it directly in the DB, so you don't
# need to edit a file and redeploy Immunity to change your configuration.
IMMUNITY_APPS = {
  :api_server => {
    :regions => [
      { :name => "sandbox1", :host => "papi-ci.us-east-1.ooyala.com" },
      { :name => "sandbox2", :host => "papi1.us-east-1.ooyala.com", :requires_manual_approval => true },
      { :name => "prod3", :host => "papi2.us-east-1.ooyala.com" },
      { :name => "prod4", :host => "papi3.us-east-1.ooyala.com" }
    ]
  }
}

