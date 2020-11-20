FROM emscripten/emsdk:2.0.6
MAINTAINER Sean Morris <sean@seanmorr.is>

SHELL ["/bin/bash", "-c"]

ARG PHP_BRANCH=PHP-7.4

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
		pv && \
	emsdk install latest
