#!/bin/sh
bundle exec rerun --pattern '{config.ru,**/*.{rb,js,css,erb,ru,html}}' -- rackup --port 3102 config.ru
