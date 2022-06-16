ARG MY_PG_VERSION
ARG PREV_IMAGE
ARG TS_VERSION
############################
# Build tools binaries in separate image
############################
ARG GO_VERSION=1.14.0
FROM golang:${GO_VERSION}-alpine AS tools
ARG MY_PG_VERSION

ENV TOOLS_VERSION 0.8.1

RUN apk update && apk add --no-cache git \
    && go get github.com/timescale/timescaledb-tune/cmd/timescaledb-tune \
    && go get github.com/timescale/timescaledb-parallel-copy/cmd/timescaledb-parallel-copy \
    && go get github.com/timescale/timescaledb-backup/cmd/ts-dump \
    && go get github.com/timescale/timescaledb-backup/cmd/ts-restore \
    && go build -o /go/bin/timescaledb-tune -v github.com/timescale/timescaledb-tune/cmd/timescaledb-tune \
    && go build -o /go/bin/timescaledb-parallel-copy -v github.com/timescale/timescaledb-parallel-copy/cmd/timescaledb-parallel-copy \
    && go build -o /go/bin/ts-dump -v github.com/timescale/timescaledb-backup/cmd/ts-dump \
    && go build -o /go/bin/ts-restore -v github.com/timescale/timescaledb-backup/cmd/ts-restore

############################
# Grab old versions from previous version
############################
ARG PREV_IMAGE
FROM ${PREV_IMAGE} AS oldversions
ARG MY_PG_VERSION
# Remove update files, mock files, and all but the last 5 .so/.sql files
RUN rm -f $(pg_config --sharedir)/extension/timescaledb*mock*.sql \
    && if [ -f $(pg_config --pkglibdir)/timescaledb-tsl-1*.so ]; then rm -f $(ls -1 $(pg_config --pkglibdir)/timescaledb-tsl-1*.so | head -n -5); fi \
    && if [ -f $(pg_config --pkglibdir)/timescaledb-1*.so ]; then rm -f $(ls -1 $(pg_config --pkglibdir)/timescaledb-*.so | head -n -5); fi \
    && if [ -f $(pg_config --sharedir)/extension/timescaledb--1*.sql ]; then rm -f $(ls -1 $(pg_config --sharedir)/extension/timescaledb--1*.sql | head -n -5); fi

############################
# Now build image and copy in tools
############################
ARG MY_PG_VERSION
FROM postgres:${MY_PG_VERSION}-bullseye
ARG OSS_ONLY
ARG MY_PG_VERSION

LABEL maintainer="Timescale https://www.timescale.com"

COPY docker-entrypoint-initdb.d/* /docker-entrypoint-initdb.d/
COPY --from=tools /go/bin/* /usr/local/bin/
COPY --from=oldversions /usr/local/lib/postgresql/timescaledb-*.so /usr/local/lib/postgresql/
COPY --from=oldversions /usr/local/share/postgresql/extension/timescaledb--*.sql /usr/local/share/postgresql/extension/

RUN apt-get update

RUN apt-get install gnupg postgresql-common apt-transport-https lsb-release wget -y

RUN /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y

RUN echo "deb https://packagecloud.io/timescale/timescaledb/debian/ $(lsb_release -c -s) main" > /etc/apt/sources.list.d/timescaledb.list

RUN wget --quiet -O - https://packagecloud.io/timescale/timescaledb/gpgkey | apt-key add -

RUN apt-get update

RUN apt-get install -y postgresql-${MY_PG_VERSION}-postgis-3

RUN apt-get install -y timescaledb-2-postgresql-${MY_PG_VERSION}

