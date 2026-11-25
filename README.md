lua-hostlist -- lua bindings for manipulating lists of hosts
============================================================

lua-hostlist is a small set of lua bindings for the `libhostlist`
code from [flux-core](https://github.com/flux-framework/flux-core),
a descendant of the hostlist code used in other LLNL projects such as
[pdsh](https://github.com/chaos/pdsh) and
[Slurm](https://github.com/SchedMD/slurm). It gives object
based access to manipulating hostlists directly from lua.

A proof-of-concept command line utility `hostlist` is provided as
a demonstration of the lua-hostlist bindings as well as a utility
for manipulating hostlist strings from the shell.

lua-hostlist is compatible with Lua 5.1 through 5.5.

The `libhostlist` sources
-------------------------

The hostlist implementation in `src/common/libhostlist` (along with
its dependency `src/common/libutil/errno_safe.h`) is copied unmodified
from flux-core, using the same directory layout, so that updates can
be applied directly from flux-core. Local changes to these files
should be avoided; fixes should go to flux-core first.

To update from a flux-core checkout in `../flux-core`:

```sh
for f in hostlist hostname hostrange util; do
    cp ../flux-core/src/common/libhostlist/$f.[ch] src/common/libhostlist/
done
cp ../flux-core/src/common/libutil/errno_safe.h src/common/libutil/
```

Installation
------------

Building requires a C compiler, `pkg-config`, and the Lua development
headers (e.g. `liblua5.4-dev` or `lua-devel`). In most cases a simple

```sh
 make && make check && make install
```

should work. This will install the `hostlist` utility into
`PREFIX/bin` (default `/usr/local/bin`), and the Lua module
`hostlist.so` into a directory under `PREFIX` that is in the default
module search path (`package.cpath`) of the Lua interpreter, e.g.
`/usr/local/lib/lua/5.4` or, with `PREFIX=/usr`, `/usr/lib64/lua/5.4`
on Fedora or `/usr/lib/x86_64-linux-gnu/lua/5.4` on Debian. If
`PREFIX` is not set and the interpreter does not search `/usr/local`,
the module is installed into the first directory in its search path.

Use `LUA` to select the Lua interpreter, and `LIBDIR` or `LUA_OBJDIR`
to set the installation directory explicitly, e.g.

```sh
 make install LUA=lua5.4 PREFIX=/usr LIBDIR=/usr/lib64
```

will install the module into `/usr/lib64/lua/5.4`.

The `hostlist` Utility
----------------------

The `hostlist` utility provided by lua-hostlist is a proof-of-concept
for the lua bindings, but may also be found to be a useful tool in
its own right. By default `hostlist` concatenates all hosts given
either on the commandline or via STDIN:

```sh
 $ hostlist foo[1-4] foo[5-10]
 foo[1-10]
```

Other operations such as count, union, intersection, exclusive or, etc.
are supported:

```
 Usage: hostlist [OPTION]... [HOSTLIST]...

  -h, --help                   Display this message.
  -q, --quiet                  Quiet output (exit non-zero if empty hostlist).
  -d, --delimiters=S           Set output delimiter (default = ",")
  -c, --count                  Print the number of hosts
  -s, --size=N                 Output at most N hosts (-N for last N hosts)
  -L, --limit=N                Same as --size
  -e, --expand                 Expand host list instead of collapsing
  -n, --nth=N                  Output the host at index N (-N to index from end)
  -u, --union                  Union of all HOSTLIST arguments
  -m, --minus                  Subtract all HOSTLIST args from first HOSTLIST
  -i, --intersection           Intersection of all HOSTLIST args
  -x, --exclude                Exclude all HOSTLIST args from first HOSTLIST
  -X, --xor                    Symmetric difference of all HOSTLIST args
  -R, --remove=N               Remove only N occurrences of args from HOSTLIST
                                (deprecated)
  -S, --sort                   Return sorted HOSTLIST
  -f, --filter=CODE            Map Lua CODE over all hosts in result HOSTLIST
                                (deprecated)
  -F, --find=HOST              Output position of HOST in result HOSTLIST
                                (exits non-zero if host not found)
```

 An arbitrary number of HOSTLIST arguments are supported for all
  operations.  The default operation is to concatenate all HOSTLIST args.

 The -R, --remove and -f, --filter options are deprecated and will be
  removed in a future release.

The lua-hostlist API
--------------------

Supported functions and methods exported from the hostlist library:

 * Create new hostlist

```lua
local hl = hostlist.new ()            -- Empty hostlist
local hl = hostlist.new (s1)          -- Hostlist from string s1
local hl = hostlist.new (s1, s2, s3)  -- Multiple args supported
```

`hostlist.new()` raises an error if a string is not a valid hostlist.
Use `pcall()` to handle invalid input:

```lua
local ok, hl = pcall (hostlist.new, s)
if not ok then
    print ("invalid hostlist: " .. hl)
end
```

There is no fixed limit on the number of hosts in a hostlist.

```sh
$ hostlist foo1 foo2 foo3
foo[1-3]
$ echo foo1 foo2 foo3 | hostlist
foo[1-3]
```

 * Expand a "compressed" hostlist

```lua
-- Expand a hostlist object into a table:
local t = hostlist.expand (s)  -- Expand string 's'
local t = hl:expand()          -- Expand hostlist object 'hl'
```

```sh
$ hostlist --expand foo[1-4]
foo1,foo2,foo3,foo4
$ hostlist --delimiters='\n' --expand foo[1-4]
foo1
foo2
foo3
foo4
```

 * Print a hostlist in lua

```lua
local hl = hostlist.new ("foo[1-5]")
print (hl)                -- promoted to string by __tostring() method
print ("hostlist" .. hl)  -- promoted to string by __concat method

--  To print an "expanded" hostlist first expand to a table, then
--   use table.concat()
print (table.concat (hl:expand(), ","))
```

 * Count hosts in a hostlist

```lua
local count = hostlist.count (s1) -- Count hosts in string s1
local count = #hl                 -- Return number of hosts in object hl
```

```sh
$ hostlist -c foo[0-3]
4
```

 * Return a host at a specific index in a hostlist:

```lua
local nth = hostlist.nth (s, n)   -- Return nth host in hostlist string s
local nth = hl[n]                 -- Same for hostlist object hl
local last = hl[-1]               -- Negative indices count from the end
```

Indices start at 1. `nil` is returned for an index that is out of range.

```sh
$ hostlist --nth=4 foo[0-100]
foo3
```

 * Find a host in a hostlist

```lua
local n = hostlist.find (s, host) -- Find host 'host' in hostlist string 's'
local n = hl:find (host)          -- Find host 'host' in hostlist object 'hl'
```

```sh
$ hostlist --find=foo3 'foo[0-10]'
4
$ hostlist --find=bar 'foo[0-10]'
$ echo $?
1
```

 * Delete (subtract) hosts

```lua
local result = hostlist.delete (s1, s2)  -- Delete hosts in s2 from s1
local result = hl1 - hl2                 -- Delete hostlist hl2 from hl1
local result = hl - "foo1"               -- Delete foo1 from hostlist hl
```

```sh
$ hostlist --minus foo[1-4] foo2
foo[1,3-4]
```

 * Union of hostlists

```lua
local result = hostlist.union (s1, s2, ...) -- Union _all_ args
local result = hl + hl2         -- Union of hostlist objects hl and hl2
local result = hl + "foo[1-4]"  -- Union of hostlist hl with a string
```

```sh
$ hostlist --union 'foo[1-5]' 'foo[4-10]'
foo[1-10]
```

 * Intersection of hostlists

```lua
local r = hostlist.intersect (s1, s2, ...)  -- Intersect of all args
local r = hl1 * hl2         -- Intersect of hostlist hl1 hl2
local r = hl * "foo[4-10]"  -- Intersect of hostlist hl and string
```

```sh
$ hostlist --intersection 'foo[1-5]' 'foo[4-10]'
foo[4-5]
```

 * XOR of hostlists

```lua
local r = hostlist.xor (s1, s2, ..)  -- XOR of all args
local r = hl1 ^ hl2                  -- XOR of two hostlist objects
local r = hl ^ "foo[4-10]"           -- XOR of hostlist hl and string
```

```sh
$ hostlist --xor 'foo[1-5]' 'foo[4-10]'
foo[1-3,6-10]
```

 * Iteration:

```lua
--  hostlist 'next' method returns an iterator for the hostlist:
for host in hl:next() do
  -- The iterator traverses a copy of hl, so it is safe to modify hl here
end

--  An alternate method is to convert to a table and use ipairs()
for _,host in ipairs (hl:expand()) do
  -- iterating over an expanded table of 'hl' here
end
```

 * Map a function across a set of hosts

```lua
hostlist.map ("foo[1-5]",
  function (s)
    -- Do something with host string in "s"
  end)
hl:map (function (s) ... end)

--  Also acts as a filter, e.g. return only hosts divisible by 10:
local hl = hostlist.new ("foo[1-100]")
local r = hl:map (function (s) return (s:match ("[%d]+$")%10 == 0) and s end)
print (r)
-- Output: foo[10,20,30,40,50,60,70,80,90,100]
```

License
-------

lua-hostlist is licensed under the GNU Lesser General Public License
version 3 (LGPL-3.0), the same license as flux-core. See `LICENSE`
and `NOTICE.LLNS` for details.

SPDX-License-Identifier: LGPL-3.0

LLNL-CODE-645467
