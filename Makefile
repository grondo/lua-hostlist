#############################################################
# Copyright 2007 Lawrence Livermore National Security, LLC
# (c.f. NOTICE.LLNS, LICENSE)
#
# This file is part of lua-hostlist.
# For details, see https://github.com/grondo/lua-hostlist.
#
# SPDX-License-Identifier: LGPL-3.0
#############################################################

LUA        ?= lua
LUA_VER    ?= $(shell $(LUA) -e 'print (_VERSION:match("Lua (.+)") )')
PREFIX_SET := $(if $(PREFIX),true,false)
PREFIX     ?= /usr/local

#  Install the Lua module into a directory in the default C module
#   search path (package.cpath) of $(LUA), so that it can be found by
#   require():
#
#   - Use the first directory in the path under $(PREFIX), skipping
#     directories under a more specific prefix (e.g. /usr/local when
#     PREFIX=/usr).
#   - Otherwise, if PREFIX was not set, use the first directory in the
#     path. Some distributions do not search /usr/local by default.
#   - Otherwise, use $(PREFIX)/lib/lua/$(LUA_VER).
#
#   LUA_CPATH* environment variables are ignored so that the result
#   does not depend on the user's environment.
#   Set LIBDIR or LUA_OBJDIR to override.
LUA_CMOD_DIR = $(shell \
	unset LUA_CPATH LUA_CPATH_5_2 LUA_CPATH_5_3 LUA_CPATH_5_4 \
	      LUA_CPATH_5_5; \
	$(LUA) -e 'prefix = "$(PREFIX)"; ver = "$(LUA_VER)"' \
	       -e 'default = not $(PREFIX_SET)' \
	       -e ' \
	    local p = prefix:gsub ("/+$$", "") \
	    local first \
	    for e in package.cpath:gmatch ("[^;]+") do \
	        local d = e:match ("^(/.+)/%?%.so$$") \
	        if d and d:sub (-#ver - 5) == "/lua/" .. ver then \
	            first = first or d \
	            local rest = d:sub (#p + 1) \
	            if d:sub (1, #p) == p and rest:match ("^/lib[^/]*/") then \
	                print (d) \
	                return \
	            end \
	        end \
	    end \
	    print (default and first or (p .. "/lib/lua/" .. ver))')

ifdef LIBDIR
LUA_OBJDIR ?= $(LIBDIR)/lua/$(LUA_VER)
else
LUA_OBJDIR ?= $(LUA_CMOD_DIR)
endif

LUA_PKG_NAME := $(shell \
	   (pkg-config --exists lua$(LUA_VER) && echo lua$(LUA_VER)) \
	|| (pkg-config --exists lua && echo lua) )

ifeq ($(LUA_PKG_NAME),)
	$(error "No Lua pkg-config file found!")
endif

LUA_CFLAGS := $(shell pkg-config --cflags $(LUA_PKG_NAME))
LUA_LIBS :=   $(shell pkg-config --libs $(LUA_PKG_NAME))

LIBHOSTLIST_SRCS := \
	src/common/libhostlist/hostlist.c \
	src/common/libhostlist/hostname.c \
	src/common/libhostlist/hostrange.c \
	src/common/libhostlist/util.c

LIBHOSTLIST_OBJS := $(LIBHOSTLIST_SRCS:.c=.o)

override CFLAGS+=  -Wall -ggdb -I. $(LUA_CFLAGS)
override LDFLAGS+= $(LUA_LIBS)

.SUFFIXES: .c .o .so

.c.o:
	$(CC) $(CFLAGS) -o $@ -fPIC -c $<

hostlist.so: lua-hostlist.o $(LIBHOSTLIST_OBJS)
	$(CC) -shared -o $*.so $^ $(LDFLAGS)

check-coverage:
	make clean
	make CFLAGS="-fprofile-arcs -ftest-coverage" LDFLAGS="-lgcov"
	make check
	gcov lua-hostlist.c
	gcov -o src/common/libhostlist $(LIBHOSTLIST_SRCS)

check: hostlist.so
	@LUAUNIT_OUTPUT=tap LUA_PATH="$(LUA_PATH);tests/?.lua" $(LUA) tests/tests.lua

install:
	install -D -m0755 hostlist.so $(DESTDIR)$(LUA_OBJDIR)/hostlist.so
	install -D -m0755 hostlist $(DESTDIR)$(PREFIX)/bin/hostlist
	@unset LUA_CPATH LUA_CPATH_5_2 LUA_CPATH_5_3 LUA_CPATH_5_4 \
	       LUA_CPATH_5_5; \
	$(LUA) -e 'dir = ("$(LUA_OBJDIR)"):gsub ("/+$$", "")' \
	       -e 'path = ";" .. package.cpath .. ";"' \
	       -e 'if path:find (";" .. dir .. "/?.so;", 1, true) then os.exit (0) end' \
	       -e 'io.stderr:write ("Warning: " .. dir .. " is not in the default package.cpath of $(LUA).\n" .. "Set LUA_CPATH to use the installed hostlist module.\n")'

clean:
	rm -f *.so *.o *.gcov *.gcda *.gcno *.core
	rm -f src/common/libhostlist/*.o \
	      src/common/libhostlist/*.gcda \
	      src/common/libhostlist/*.gcno
