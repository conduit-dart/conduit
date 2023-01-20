FROM dart:stable

COPY packages/ packages/
COPY melos.yaml melos.yaml
RUN dart pub global activate -spath packages/cli
RUN dart pub global activate melos
ENV PUB_CACHE=/root/.pub-cache
ENV PATH=$PATH:$PUB_CACHE/bin
RUN melos cache-source
