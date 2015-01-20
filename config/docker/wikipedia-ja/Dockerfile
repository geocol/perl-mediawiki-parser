FROM debian:sid

RUN apt-get update
RUN apt-get -y install perl wget git bzip2 make gcc tar

RUN git clone git://github.com/geocol/perl-mediawiki-parser
RUN cd perl-mediawiki-parser && make deps PMBP_OPTIONS=--execute-system-package-installer
RUN cd perl-mediawiki-parser && make -f Makefile.data data-ja

RUN echo '{"ja": {"cache_dir_name": "/perl-mediawiki-parser/local/wpserver/cache/ja", "dump_file_name": "/perl-mediawiki-parser/local/wpserver/xml/ja.xml"}}' > /keys.json

RUN echo '#!/bin/bash\nexport LANG=C\nexport TZ=UTC\nexport WPSERVER_KEY_MAPPING=/keys.json\nwhile true\ndo\n  perl-mediawiki-parser/plackup -s Twiggy::Prefork -p 4513 perl-mediawiki-parser/bin/wpserver.psgi\ndone' > /server
RUN chmod u+x /server
