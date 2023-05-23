FROM dart:stable

COPY ci/ ci/
COPY packages/ packages/
COPY melos.yaml melos.yaml
COPY pubspec.yaml pubspec.yaml
RUN dart pub global activate -spath packages/cli
RUN dart pub global activate melos
ENV PUB_CACHE=/root/.pub-cache
ENV PATH=$PATH:$PUB_CACHE/bin
RUN melos cache-source
RUN dart --disable-analytics