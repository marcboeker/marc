# Build from source

You need macOS 26 or later and Xcode 27.

```sh
git clone https://github.com/marcboeker/marcdown
cd marcdown
make install
```

This copies `Marcdown.app` to `~/Applications` and puts a symbolic link to the `marcdown` command in
`~/.local/bin`. Make sure that `~/.local/bin` is in your `PATH`. To use different folders, set
`APPDIR` or `PREFIX`, for example `make install APPDIR=/Applications PREFIX=/usr/local`.

You can also install the command later from the app: **Marcdown → Install Command Line Tool…**.
