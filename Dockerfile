FROM alpine:latest as builder
LABEL org.opencontainers.image.authors "suvl (https://github.com/suvl), selfhosting-tools (https://github.com/selfhosting-tools)"

ARG UNBOUND_VERSION=1.19.0
ARG GPG_FINGERPRINT="EDFAA3F2CA4E6EB05681AF8E9F6F1C2D7E045F8D"
ARG SHA256_HASH="a97532468854c61c2de48ca4170de854fd3bc95c8043bb0cfb0fe26605966624"


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
   curl -OO https://www.nlnetlabs.nl/downloads/unbound/unbound-${UNBOUND_VERSION}.tar.gz{,.asc} && \
   echo "Verifying authenticity of unbound-${UNBOUND_VERSION}.tar.gz..." && \
   CHECKSUM=$(sha256sum unbound-${UNBOUND_VERSION}.tar.gz | awk '{print $1}') && \
   if [ "${CHECKSUM}" != "${SHA256_HASH}" ]; then echo "ERROR: Checksum does not match!" && exit 1; fi && \
   ( \
      gpg --recv-keys ${GPG_FINGERPRINT} || \
      gpg --keyserver pgp.mit.edu --recv-keys ${GPG_FINGERPRINT} \
   ) && \
   FINGERPRINT="$(LANG=C gpg --verify unbound-${UNBOUND_VERSION}.tar.gz.asc unbound-${UNBOUND_VERSION}.tar.gz 2>&1 \
                | sed -n 's#^Primary key fingerprint: \(.*\)#\1#p' | tr -d '[:space:]')" && \
   if [ -z "${FINGERPRINT}" ]; then echo "ERROR: Invalid GPG signature!" && exit 1; fi && \
   if [ "${FINGERPRINT}" != "${GPG_FINGERPRINT}" ]; then echo "ERROR: Wrong GPG fingerprint!" && exit 1; fi && \
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


FROM alpine:latest
LABEL org.opencontainers.image.authors "suvl (https://github.com/suvl), selfhosting-tools (https://github.com/selfhosting-tools)"

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
