# Package
version     = "0.7.7"
author      = "Charles Blake"
description = "Minimalistic Kernel-Syslogd For Linux in Nim"
license     = "MIT/ISC"
bin         = @[ "kslog_open", "kslog", "cp_trunc" ]

# Dependencies
requires "nim >= 0.20", "cligen >= 1.7.8"
