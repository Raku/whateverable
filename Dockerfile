FROM rakudo-star:2023.02
WORKDIR /srv

RUN apt-get -y update
RUN apt-get -y upgrade
RUN apt-get -y install zstd lrzip libssl-dev build-essential

RUN git config --global --add safe.directory '*'

COPY META6.json /srv
RUN zef install --force --/test HTTP::HPACK # to work around the dependency issue
RUN zef install --force --/test --deps-only .

COPY .git/ /srv/.git/
COPY . /srv
