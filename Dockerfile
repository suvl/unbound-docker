FROM alpine:3.22.0@sha256:8a1f59ffb675680d47db6337b49d22281a139e9d709335b492be023728e11715 AS builder
# checkov:skip=CKV_DOCKER_3: This is a builder image, so it is not necessary to run as a non-root user.

LABEL org.opencontainers.image.authors="suvl (https://github.com/suvl), selfhosting-tools (https://github.com/selfhosting-tools)"

ARG UNBOUND_VERSION=1.23.0
ARG SHA256_HASH="959bd5f3875316d7b3f67ee237a56de5565f5b35fc9b5fc3cea6cfe735a03bb8"

RUN apk add --no-cache \
      bash \
      curl \
      gnupg \
      build-base \
      libevent-dev \
      openssl-dev \
      expat-dev \
      ca-certificates \
      nghttp2-dev

SHELL [ "/bin/bash", "-o", "pipefail", "-c" ]

WORKDIR /tmp
RUN \
   curl -OO https://www.nlnetlabs.nl/downloads/unbound/unbound-${UNBOUND_VERSION}.tar.gz && \
   echo "Verifying authenticity of unbound-${UNBOUND_VERSION}.tar.gz..." && \
   CHECKSUM=$(sha256sum unbound-${UNBOUND_VERSION}.tar.gz | awk '{print $1}') && \
   if [ "${CHECKSUM}" != "${SHA256_HASH}" ]; then echo "ERROR: Checksum does not match!" && exit 1; fi && \
   echo "SHA256 and GPG signature are correct"

RUN echo "Extracting unbound-${UNBOUND_VERSION}.tar.gz..." && \
    tar -xzf "unbound-${UNBOUND_VERSION}.tar.gz"
WORKDIR /tmp/unbound-${UNBOUND_VERSION}

RUN ./configure --prefix="" --with-libnghttp2 \
    CFLAGS="-O2 -flto -fPIE -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=2 -fstack-protector-strong \
            -Wformat -Werror=format-security" \
    LDFLAGS="-Wl,-z,now -Wl,-z,relro" && \
    make && \
    make install DESTDIR=/builder


FROM alpine:3.22.0@sha256:8a1f59ffb675680d47db6337b49d22281a139e9d709335b492be023728e11715
LABEL org.opencontainers.image.authors="suvl (https://github.com/suvl), selfhosting-tools (https://github.com/selfhosting-tools)"

ENV UID=991

RUN adduser -u ${UID} -s /bin/nologin -h /etc/unbound --disabled-password unbound && \
   apk add --no-cache \
      openssl \
      expat \
      tini \
      nghttp2

COPY --from=builder /builder /
COPY run.sh /usr/local/bin

VOLUME /etc/unbound
EXPOSE 53 53/udp

HEALTHCHECK --interval=10s --timeout=5s --start-period=10s CMD unbound-control status

CMD ["run.sh"]
