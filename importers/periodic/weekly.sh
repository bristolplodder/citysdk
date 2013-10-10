#!/bin/bash

log=/usr/local/nginx/logs/weekly.citysdk.log
touch "$log"
date >> "$log"

. /usr/local/rvm/scripts/rvm
ruby=`which ruby`

for i in /var/www/citysdk/shared/periodic/weekly/*.rb
do
    if test -f "$i" 
    then
      $ruby $i >> "$log"
    fi
done

cd /var/www/citysdk/shared/importers/gtfs && $ruby update_feeds.rb >> "$log"


