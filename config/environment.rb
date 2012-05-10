DB_LOCATION = "DBI:Mysql:immunity_system:localhost"
DB_USER = "root"
DB_PASSWORD = ""
IMMUNITY_SERVER_PORT = 3102

REDIS_HOST = ENV["REDIS_HOST"] || "localhost"
REDIS_PORT = ENV["REDIS_PORT"] || 6379

LOG_FORWARDER_PORT = 4569

# This redis hostname needs to be accessible by remote machines who will be putting log lines into it.
# e.g. i.e. "localhost" in production.
LOG_FORWARDING_REDIS_HOST = "localhost"