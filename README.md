<!--
SPDX-FileCopyrightText: © 2025 Mark Delk <jethrodaniel@gmail.com>

SPDX-License-Identifier: MIT
-->

# mruby.zig

Build [mruby](https://github.com/mruby/mruby) using [zig](https://ziglang.org) (no rake!).

## About

> Yeah, but your scientists were so preoccupied with whether or not they could, they didn't stop to think if they should.
>
> --- Jeff Goldblum (Jurassic Park, 1993)

This project builds MRuby from source, only using Zig.

This means we emulate MRuby's non-trivial Rake-based build process entirely in Zig.

**NOTE**: We only support zig 0.14.1 at the moment.

## Issues

- Non-standard library gems that use any Ruby logic in their `mrbgem.rake` files aren't supported
- Symbol preallocation isn't supported (this depends on Ruby regex to create the C files)
- Using `mruby.zig` in transitive Zig dependencies will likely cause issues (just use it globally in one package for now)
- We have to fork MRuby just to add back `mrbgems/mruby-compiler/core/y.tab.c`

## Usage

### Command line tools

To install all the CLI programs:

```
zig build
```
```
$ tree zig-out/bin/
zig-out/bin/
├── example-c
├── example-zig
├── host-mrbc
├── mirb
├── mrbc
├── mrbtest
├── mruby
└── mruby-strip
```

See `zig build -h` for information about everything that's available:

```
zig build -h
```
```
Usage: /path/to/zig build [steps] [options]

Steps:
  install (default)            Copy build artifacts to prefix path
  uninstall                    Remove build artifacts from prefix path
  mrbc                         Run mrbc
  host-mrbc                    Run host-mrbc
  mruby                        Run mruby
  mirb                         Run mirb
  mrdb                         Run mrdb
  mruby-strip                  Run mruby-strip
  mrbtest                      Run mrbtest
  example-c                    Run src/example.c
  example-rb                   Run src/example.rb
  example-zig                  Run src/example.zig
```

To run MRuby's tests:

```
zig build mrbtest
```
```
mrbtest - Embeddable Ruby Test

...............................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................................
  Total: 1647
     OK: 1647
     KO: 0
  Crash: 0
Warning: 0
   Skip: 0
   Time: 1.07 seconds

```

To use `mirb`, `mruby`, etc:

```console
$ zig build mirb
mirb - Embeddable Interactive Ruby Shell

> MRUBY_VERSION
 => "3.4.0"
```

### Examples

To run the examples:

```
zig build example-c
zig build example-rb
zig build example-zig
```

### Cross compilation

Linux/Mac are the only targets currently supported, but support for others shouldn't be difficult.

```
zig build -Doptimize=ReleaseFast -Dtarget=x86_64-macos-none
zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux-musl
zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux-gnu
```

### Using in a Zig project

Add to your `build.zig.zon`:

```
zig fetch --save=mruby "git+https://github.com/jethrodaniel/mruby.zig#main"
```

Then update your `build.zig` like so:

```
TODO
```

For more detail, see the `example-zig` step in [build.zig](build.zig), and the example file, [src/example.zig](src/example.zig).

TODO: document creating and using custom gems, using only a subset of the standard library, etc

## Contributing

Bug reports and pull requests are welcome at https://github.com/jethrodaniel/mruby.zig

## Acknowledgements

This project was inspired by https://github.com/dantecatalfamo/mruby-zig (MIT):

Some differences:

- we use `@cImport` instead of zig bindings
- we use `zig build` instead of `rake`

## License

[MIT](https://spdx.org/licenses/MIT.html), same as [MRuby](https://github.com/mruby/mruby).
