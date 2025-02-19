// SPDX-FileCopyrightText: © 2025 Mark Delk <jethrodaniel@gmail.com>
//
// SPDX-License-Identifier: MIT

// https://mruby.org/docs/articles/executing-ruby-code-with-mruby.html

#include <mruby.h>
#include <mruby/compile.h>

#include <stdio.h>
#include <stdlib.h>

#include <mruby/gc.h>

int main(void) {
  mrb_state *mrb = mrb_open();

  if (!mrb) {
    fprintf(stderr, "mrb_open");
    exit(-1);
  }

  // mrb_load_string(mrb, str) to load from NULL terminated strings
  // mrb_load_nstring(mrb, str, len) for strings without null terminator or with
  // known length
  mrb_value result = mrb_load_string(mrb, "21 * 2");

  // NOTE: require mruby0io and mruby-compiler
  mrb_load_string(mrb, "puts Time");

  mrb_int ret = mrb_integer(result);

  mrb_close(mrb);

  printf("sizeof(mrb_gc): %d\n", sizeof(mrb_gc));

  return ret;
}
