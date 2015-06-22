FROM wakaba/docker-perl-app-base

RUN mv /app /app.orig && \
    git clone git://github.com/geocol/perl-mediawiki-parser /app && \
    mv /app.orig/* /app/ && \
    cd /app && PMBP_DUMP_BEFORE_DIE=1 make deps PMBP_OPTIONS=--execute-system-package-installer && \
    echo '#!/bin/bash' > /server && \
    echo 'cd /app && WPSERVER_KEY_MAPPING=/config/keys.json ./plackup bin/server.psgi -p 8080 -s Twiggy' >> /server && \
    chmod u+x /server && \
    rm -fr /app/deps /app.orig
