FROM rakudo-star:2023.08
WORKDIR /srv

RUN apt-get -y update
RUN apt-get -y upgrade
RUN apt-get -y install zstd lrzip libssl-dev build-essential

COPY META6.json /srv
RUN zef install --force --/test --deps-only .

COPY . /srv
