#!/bin/bash
export LANG=C
export TZ=UTC
export WPSERVER_KEY_MAPPING=/keys.json

while true
do
  perl-mediawiki-parser/plackup -s Twiggy::Prefork -p 4513 \
      perl-mediawiki-parser/bin/wpserver.psgi
done
