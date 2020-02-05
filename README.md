I mostly wrote this because I wanted to run my kernel/system logger not as
root.  I looked into doing this with `syslog-ng` and it seemed hard to get
right.  `CAP_SYS_ADMIN` or whatnot also seem used.  I had a hunch that over
the years feature bloat had exploded sysloggers beyond reason making what I
wanted unnecessarily difficult.  For what most people use it for, it should
really be a simple program anyway.  syslog-ng is over 300,000 lines of C.
Even busybox syslogd clocks in at over 1,000 lines.

Instead of all that jazz, I give you `kslog` - under 200 lines of Nim that
likely does all you really need in two easy pieces - a few dozen line easily
audited privileged `kslog_open.nim` and 125-ish line `kslog.nim`.

Sadly, `kslog-open` (*not* `kslog`) must run as root to manipulate `/dev/`.
At this late date, there is probably no relocating of `/dev/log` or making
binding of Unix domain sockets easier.  This opening phase is *all* `kslog`
needs elevated privilege for.  `kslog-open` just does this minimal work to
set up input file descriptors 0,3 and then drops privilege & exec's `kslog`.
`kslog` itself only needs permission to open its output files for write.
If said output files already exist with `syslog`-user writable permission,
the `syslog` user need not even have permission to create new files in
`/var/log`.  Wide ability to write to `/dev/log` always affords an easy
fill-the-disk attack, of course.

Priority & facility numbers are retained in `kslog` logs.  I doubt there
is a better way to decide if you want to filter out informational or debug
messages by altering `maxLevel` than looking at a big list of examples.
`grep '\<P[67],F[0-9]' /var/log/msgs` does just that.  Personally, I keep
all priority levels, but retention also makes it easy to grep for important
things, too.  I think dropping these fields (and calendar years!) harkens
to disk space concerns long since past.

Personally, I only do this every several years or so, but if disk space in
`/var/log/` is at a premium (a bad idea, but sometimes things happen), you
can still rotate logs.  Since `kslog` never re-opens output files, showing
how to do this reliably here is warranted.  Would be external log rotators
should SIGSTOP `kslog`, copy files, then truncate logs to zero, then SIGCONT.
To avoid losing msgs from filled backlogs, care should be taken to not leave
`kslog` suspended indefinitely or even very long.  An example shell script is
`log-arch` using the also included `cp_trunc.nim` program which usually only
has to suspend kslog for "around milliseconds".  Considering times are only
1-second resolution, it is doubtful that delay would ever matter.

When you want remote logs on some more trusted machine then I recommend
providing remote `rsync` access to local logs made by `kslog`.  Provided
this access is one-way (trusted can access `kslogs` but not vice versa),
I'd think this adequate protection/detection from intruders altering logs.
It is much lower tech just using ssh/rsync/etc. which you likely already
know how to use and additionally supports logs updated by entities other
than syslog (e.g. `wtmp`).  Detecting even transient revocation of such
access by an intruder is also easy.  This idea does not solve the problem
of literally zero local space for logs.  That problem is perhaps best
addressed by an independent specialized tool, like a hypothetical `logfwd`
(that should also support non-syslog logs!).  In short, this whole topic
is about file replication and management, not system logging directly.
