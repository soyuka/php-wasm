# WASM PHP

Project based on https://github.com/seanmorris/php-wasm which was forked from https://github.com/oraoto/pib

I fixed some inconsistencies in the Makefile and removed non-essential things. This fork:
  - does build SQLITE3 (TODO add this back opt-in)
  - does build Libxml
  - has no javascript abstraction
  - does not build https://github.com/seanmorris/vrzno which allows javascript access from PHP (TODO add this back opt-in cause it's really cool)
  - does not add preloaded data, having this separatly from php-wasm builds allows for more flexibility
  - exposes FS and builds with [IDBFS](https://emscripten.org/docs/api_reference/Filesystem-API.html#FS.syncfs)
  - reduces memory to 256mb

## Build 

```
docker pull soyuka/php-emscripten-builder
make
```

Builded files will be located in `build/php-web.js` and `build/php-web.wasm`. 

## Usage

The builded PHP WASM version exposes these functions that will help you execute PHP: `_pib_init`, `_pib_destroy`, `_pib_run`, `_pib_exec`, `_pib_refresh`. The source code behind them is located under `source/pib_eval.c` and the exported function are declared in the final build command (see `Makefile`). To call these, you'll use [`ccall`](https://emscripten.org/docs/porting/connecting_cpp_and_javascript/Interacting-with-code.html#interacting-with-code-ccall-cwrap), for example:

```
const phpBinary = require('build/php-web');

return phpBinary({
    onAbort: function(reason) {
      console.error('WASM aborted: ' + reason)
    },
    print: function (...args) {
      console.log('stdout: ', args)
    },
    printErr: function (...args) {
      console.log('stderr: ', args)
    }
})
.then(({ccall, FS}) => {
  const phpVersion = ccall(
    'pib_exec'
    , 'string'
    , ['string']
    , [`phpversion();`]
  );
})
```

Thanks to [@seanmorris](https://github.com/seanmorris/php-wasm) you can also use persistent calls to keep things in memory by using:

```
let retVal = ccall(
  'pib_init'
  , NUM
  , [STR]
  , []
);

console.log('PHP initialized', retVal)

function runCode(phpCode) {
  ccall(
    'pib_run'
    , NUM
    , [STR]
    , [`?>${phpCode}`]
  )
}

// Remove things kept in-memory
function refresh() {
  ccall(
    'pib_refresh'
    , NUM
    , []
    , []
  );
}
```

More examples on the code usage are available on [@seanmorris's repository](https://github.com/seanmorris/php-wasm/tree/master/docs-source) or on [APIPlatform By Examples]().
