# Build from source

You need macOS 26 or later and Xcode 27.

```sh
git clone https://github.com/marcboeker/marc
cd marc
make install
```

This copies `Marc.app` to `~/Applications` and puts a symbolic link to the `marc` command in
`~/.local/bin`. Make sure that `~/.local/bin` is in your `PATH`. To use different folders, set
`APPDIR` or `PREFIX`, for example `make install APPDIR=/Applications PREFIX=/usr/local`.

You can also install the command later from the app: **Marc → Install Command Line Tool…**.
