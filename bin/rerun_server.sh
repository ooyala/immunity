#!/bin/sh
bundle exec rerun -x --pattern '{config.ru,lib/**/*.rb,*.rb}' -- rackup --port 3102 config.ru