##*****************************************************************************
## Copyright (C) 2007-2013 Lawrence Livermore National Security, LLC.
## Produced at Lawrence Livermore National Laboratory.
##
## LLNL-CODE-645467. All Rights Reserved.
##
## This file is part of lua-hostlist.
##
## This is free software: you can redistribute it and/or modify it
## under the terms of the GNU General Public License (as published by the
## Free Software Foundation) version 2, dated June 1991.
##
## This program is distributed in the hope that it will be useful, but
## WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
## or FITNESS FOR A PARTICULAR PURPOSE.  See the terms and conditions of the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## and GNU Lesser General Public License along with MUNGE.  If not, see
## <http://www.gnu.org/licenses/>.
##*****************************************************************************

LUA        ?= lua
LUA_VER    ?= $(shell $(LUA) -e 'print (_VERSION:match("Lua (.+)") )')
LIBDIR     ?= /usr/local/lib
LUA_OBJDIR ?= $(LIBDIR)/lua/$(LUA_VER)
PREFIX     ?= /usr/local

LUA_PKG_NAME := $(shell \
	   (pkg-config --exists lua$(LUA_VER) && echo lua$(LUA_VER)) \
	|| (pkg-config --exists lua && echo lua) )

ifeq ($(LUA_PKG_NAME),)
	$(error "No Lua pkg-config file found!")
endif

LUA_CFLAGS := $(shell pkg-config --cflags $(LUA_PKG_NAME))
LUA_LIBS :=   $(shell pkg-config --libs $(LUA_PKG_NAME))

override CFLAGS+=  -Wall -ggdb $(LUA_CFLAGS)
override LDFLAGS+= $(LUA_LIBS)

.SUFFIXES: .c .o .so

.c.o:
	$(CC) $(CFLAGS) -o $@ -fPIC -c $<

hostlist.so: hostlist.o lua-hostlist.o
	$(CC) -shared -o $*.so $^ $(LDFLAGS)

check-coverage:
	make clean
	make CFLAGS="-fprofile-arcs -ftest-coverage" LDFLAGS="-lgcov"
	make check
	gcov lua-hostlist.c
	gcov hostlist.c

check: hostlist.so
	LUA_PATH="$(LUA_PATH);tests/?.lua" $(LUA) tests/tests.lua

install:
	install -D -m0755 hostlist.so $(DESTDIR)$(LUA_OBJDIR)/hostlist.so
	install -D -m0755 hostlist $(DESTDIR)$(PREFIX)/bin/hostlist

clean:
	rm -f *.so *.o *.gcov *.gcda *.gcno *.core
