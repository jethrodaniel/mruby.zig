# SPDX-FileCopyrightText: © 2025 Mark Delk <jethrodaniel@gmail.com>
#
# SPDX-License-Identifier: MIT

class Example
  def inspect = "#<#{self.class}:42>"
end

if respond_to?(:puts)
  puts MRUBY_DESCRIPTION
  puts MRUBY_COPYRIGHT

  puts Example.new.inspect
end

42
