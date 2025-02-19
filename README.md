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

TODO

```
zig build mirb
zig build mruby
zig build mrdb

# etc, see `zig build -h` or the `build.zig`
```

Building for other targets - e.g, on Linux

```
zig build -Dtarget=x86_64-macos-none -p macos
zig build -Dtarget=x86_64-linux-musl -p musl
```

## License

[MIT](https://spdx.org/licenses/MIT.html), same as [MRuby](https://github.com/mruby/mruby).
