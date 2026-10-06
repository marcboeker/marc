# Development

To build and install Marc, see [BUILD.md](BUILD.md).

```sh
make run     # build a debug version and open it
make test    # run the unit tests
make build   # build only
make clean   # remove the build output
```

The editor is a fork of [swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine)
in `Packages/MarkdownEngine`. Marc also uses [swift-markdown](https://github.com/swiftlang/swift-markdown)
for format and lint, [Demark](https://github.com/steipete/Demark) for HTML to Markdown, and
[swift-cmark](https://github.com/swiftlang/swift-cmark) for print and the rendered preview. See
[DESIGN.md](../DESIGN.md) for the design.
