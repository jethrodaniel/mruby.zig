<!--
SPDX-FileCopyrightText: © 2025 Mark Delk <jethrodaniel@gmail.com>

SPDX-License-Identifier: MIT
-->

# mruby.zig

Build [mruby](https://github.com/mruby/mruby) using [zig](https://ziglang.org) (no rake!).

## About

> Yeah, but your scientists were so preoccupied with whether or not they could, they didn't stop to think if they should.
>
> Jeff Goldblum

This project builds MRuby entirely from source, only using Zig.

This means we emulate MRuby's non-trivial build process entirely in Zig.

## What doesn't work

- non-standard library gems that use any custom Ruby logic in their `mrbgem.rake`
- preallocation of symbols (this depends on Ruby regex)
- `mruby.zig` in transitive Zig dependencies (just use it globally in one package for now)

## What does work

Pretty much everything else.

### Command line tools and examples

```
$ zig build -h
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

For example, to run the MRuby tests

```
zig build -Doptimize=ReleaseFast

# or just `zig build mrbtest` directly
./zig-out/bin/mrbtest
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

```
./zig-out/bin/mruby -v
mruby 3.3.0 (2024-02-14)

$ ./zig-out/bin/mirb
mirb - Embeddable Interactive Ruby Shell

> MRUBY_VERSION
 => "3.3.0"
```

### Cross compilation

Linux/Mac are the only targets currently supported, but support for others shouldn't be difficult.

```
zig build -Doptimize=ReleaseFast -Dtarget=x86_64-macos-none
zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux-musl
zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux-gnu
```

### Using in a Zig project

TODO: document this

## Contributing

Bug reports and pull requests are welcome at https://github.com/jethrodaniel/mruby.zig

## License

[MIT](https://spdx.org/licenses/MIT.html), same as [MRuby](https://github.com/mruby/mruby).
