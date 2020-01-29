#!/bin/sh
#NOTE: nimble does not seem to allow binary executable names to differ from
#      nim module names.  Most Unix people prefer "cp-trunc" over "cp_trunc".
#      So, if you want `log-arch` and `kslog.openrc` to work unmodified then
#      either create compatibilty symlinks or just 'mv cp_trunc cp-trunc' and
#      likewise for kslog_open upon installation or use this build script.
#      I do not use nimble to install things myself.  Also, Araq supports '-'
#      in module names.  https://forum.nim-lang.org/t/5024#31561
#      So, someday this may all be more frictionless.

nim c -d:release kslog_open
nim c -d:release kslog
nim c -d:release cp_trunc
