-include .env

UID?=1000 # Change this in your .env file if you're not UID 1001

ENVIRONMENT    ?=web
INITIAL_MEMORY ?=1gb
PRELOAD_ASSETS ?=/src/preload/
ASSERTIONS     ?=0
OPTIMIZE       ?=-O1
RELEASE_SUFFIX ?=

PHP_BRANCH     ?=php-8.0.0
LIBXML2_TAG    ?=v2.9.10

DOCKER_ENV=docker-compose -p phpwasm run --rm \
	-e UID=${UID} \
	-e INITIAL_MEMORY=${INITIAL_MEMORY}   \
	-e LIBXML_LIBS="-L/src/lib/lib" \
	-e LIBXML_CFLAGS="-I/src/lib/include/libxml2" \
	-e SQLITE_CFLAGS="-I/src/third_party/sqlite-src" \
	-e SQLITE_LIBS="-L/src/third_party/sqlite-src" \
  -e PRELOAD_ASSETS='${PRELOAD_ASSETS}' \
	-e ENVIRONMENT=${ENVIRONMENT}         

DOCKER_RUN           =${DOCKER_ENV} emscripten-builder
DOCKER_RUN_IN_PHP    =${DOCKER_ENV} -w /src/third_party/php-src/ emscripten-builder
DOCKER_RUN_IN_LIBXML =${DOCKER_ENV} -w /src/third_party/libxml2/ emscripten-builder

.PHONY: web all clean image js hooks push-image pull-image

web: lib/pib_eval.o php-web.wasm
all: php-web.wasm php-webview.wasm php-node.wasm php-shell.wasm php-worker.wasm js
	@ echo "Done!"

########### Collect & patch the source code. ###########

third_party/sqlite-src/sqlite3.c:
	wget https://sqlite.org/2020/sqlite-amalgamation-3330000.zip
	${DOCKER_RUN} unzip sqlite-amalgamation-3330000.zip
	${DOCKER_RUN} rm sqlite-amalgamation-3330000.zip
	${DOCKER_RUN} mv sqlite-amalgamation-3330000 third_party/sqlite-src

third_party/php-src/patched: third_party/sqlite-src/sqlite3.c
	${DOCKER_RUN} git clone https://github.com/php/php-src.git third_party/php-src \
		--branch ${PHP_BRANCH}   \
		--single-branch          \
		--depth 1
	${DOCKER_RUN} cp -v third_party/sqlite-src/sqlite3.h third_party/php-src/main/sqlite3.h
	${DOCKER_RUN} cp -v third_party/sqlite-src/sqlite3.c third_party/php-src/main/sqlite3.c
	${DOCKER_RUN} git apply --directory=third_party/php-src --no-index patch/${PHP_BRANCH}.patch
	${DOCKER_RUN} touch third_party/php-src/patched

third_party/libxml2/README:
	${DOCKER_RUN} git clone https://gitlab.gnome.org/GNOME/libxml2.git third_party/libxml2 \
		--branch ${LIBXML2_TAG} \
		--single-branch     \
		--depth 1

third_party/libxml2/configure: third_party/libxml2/README
	${DOCKER_RUN_IN_LIBXML} ./autogen.sh
	${DOCKER_RUN_IN_LIBXML} emconfigure ./configure --prefix=/src/lib/ --enable-static --disable-shared \
		--with-python=no --with-threads=no
	${DOCKER_RUN_IN_LIBXML} emmake make -j6
	${DOCKER_RUN_IN_LIBXML} emmake make install

########### Build the objects. ###########

third_party/php-src/configure: third_party/php-src/patched third_party/libxml2/configure
	${DOCKER_RUN_IN_PHP} bash -c "./buildconf --force && emconfigure ./configure \
		--enable-embed=static \
		--with-layout=GNU  \
		--with-libxml      \
		--enable-xml       \
		--disable-cgi      \
		--disable-cli      \
		--disable-all      \
		--with-sqlite3     \
		--enable-session   \
		--enable-filter    \
		--enable-calendar  \
		--enable-dom       \
		--enable-pdo       \
		--with-pdo-sqlite  \
		--disable-rpath    \
		--disable-phpdbg   \
		--without-pear     \
		--with-valgrind=no \
		--without-pcre-jit \
		--enable-bcmath    \
		--enable-json      \
		--enable-ctype     \
		--enable-mbstring  \
		--disable-mbregex  \
		--enable-tokenizer \
		--enable-simplexml   \
	"

lib/libphp.a: third_party/php-src/configure third_party/php-src/patched third_party/sqlite-src/sqlite3.c
	${DOCKER_RUN_IN_PHP} emmake make -j6
	${DOCKER_RUN} cp -v third_party/php-src/.libs/libphp.la third_party/php-src/.libs/libphp.a lib/

lib/pib_eval.o: lib/libphp.a source/pib_eval.c
	${DOCKER_RUN_IN_PHP} emcc ${OPTIMIZE} \
		-I .     \
		-I Zend  \
		-I main  \
		-I TSRM/ \
		-I /src/third_party/libxml2 \
		-I /src/third_party/sqlite-src \
		-c \
		/src/source/pib_eval.c \
		-o /src/lib/pib_eval.o \
		-s ERROR_ON_UNDEFINED_SYMBOLS=0 

########### Build the final files. ###########

FINAL_BUILD=${DOCKER_RUN_IN_PHP} emcc ${OPTIMIZE} \
	-o ../../build/php-${ENVIRONMENT}${RELEASE_SUFFIX}.js \
	--llvm-lto 2                     \
	-s EXPORTED_FUNCTIONS='["_pib_init", "_pib_destroy", "_pib_run", "_pib_exec", "_pib_refresh", "_main", "_php_embed_init", "_php_embed_shutdown", "_php_embed_shutdown", "_zend_eval_string"]' \
	-s EXTRA_EXPORTED_RUNTIME_METHODS='["ccall", "UTF8ToString", "lengthBytesUTF8"]' \
	-s ENVIRONMENT=${ENVIRONMENT}    \
	-s FORCE_FILESYSTEM=1            \
	-s MAXIMUM_MEMORY=2gb             \
	-s INITIAL_MEMORY=${INITIAL_MEMORY} \
	-s ALLOW_MEMORY_GROWTH=1         \
	-s ASSERTIONS=${ASSERTIONS}      \
	-s ERROR_ON_UNDEFINED_SYMBOLS=0  \
	-s EXPORT_NAME="'PHP'"           \
	-s MODULARIZE=1                  \
	-s INVOKE_RUN=0                  \
	-lidbfs.js                       \
		/src/lib/pib_eval.o /src/lib/libphp.a /src/lib/lib/libxml2.a

php-web.wasm: ENVIRONMENT=web
php-web.wasm: lib/libphp.a lib/pib_eval.o 
	${FINAL_BUILD}

php-worker.wasm: ENVIRONMENT=worker
php-worker.wasm: lib/libphp.a lib/pib_eval.o
	${FINAL_BUILD}

php-node.wasm: ENVIRONMENT=node
php-node.wasm: lib/libphp.a lib/pib_eval.o
	${FINAL_BUILD}

php-shell.wasm: ENVIRONMENT=shell
php-shell.wasm: lib/libphp.a lib/pib_eval.o
	${FINAL_BUILD}

php-webview.wasm: ENVIRONMENT=webview
php-webview.wasm: lib/libphp.a lib/pib_eval.o
	${FINAL_BUILD}

########### Clerical stuff. ###########

clean:
	${DOCKER_RUN} rm -fv  *.js *.wasm *.data
	${DOCKER_RUN} rm -rfv  build/* lib/*
	${DOCKER_RUN} rm -rfv third_party/php-src
	${DOCKER_RUN} rm -rfv third_party/libxml2
	${DOCKER_RUN} rm -rfv third_party/sqlite-src

hooks:
	@ git config core.hooksPath githooks

js:
	@ npm install | ${TIMER}
	@ npx babel source --out-dir . | ${TIMER}

image:
	@ docker-compose build

pull-image:
	@ docker-compose pull

push-image:
	@ docker-compose push

preload-data:
	${DOCKER_RUN_IN_PHP} python3 /emsdk/upstream/emscripten/tools/file_packager.py ../../build/php-web.data \
		--preload ${PRELOAD_ASSETS} \
		--js-output=../../build/php-web.data.js

