FROM dart:stable

COPY packages/ packages/
COPY melos.yaml melos.yaml
RUN dart pub global activate -spath packages/cli
RUN dart pub global activate melos
RUN melos cache-source