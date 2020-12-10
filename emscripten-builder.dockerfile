FROM emscripten/emsdk:2.0.10
MAINTAINER Sean Morris <sean@seanmorr.is>

SHELL ["/bin/bash", "-c"]

RUN apt-get update && \
	apt-get --no-install-recommends -y install \
		build-essential \
		automake \
		autoconf \
		libtool \
		pkgconf \
    python3 \
		bison \
		flex \
		make \
		re2c \
		gdb \
		git \
    libxml2 \
    libxml2-dev \
		pv \
    re2c
