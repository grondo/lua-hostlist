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

LIBDIR ?=      /usr/local/lib
LUA_OBJDIR ?=  $(LIBDIR)/lua/$(LUA_VER)
PREFIX ?=      /usr/local


all: hostlist.so

hostlist_OBJS = hostlist.o lua-hostlist.o

.SUFFIXES: .c .o .so

.c.o:
	$(CC) -fPIC -g -Wall -c $<

hostlist.so: $(hostlist_OBJS)
	$(CC) -shared -o $*.so $^ $(LDFLAGS) $(LIBS)

check: hostlist.so
	@(cd tests && LUA_CPATH=../?.so ./lunit tests.lua)

install:
	install -D -m0644 hostlist.so $(DESTDIR)$(LUA_OBJDIR)/hostlist.so
	install -D -m0755 hostlist $(DESTDIR)$(PREFIX)/bin/hostlist

clean:
	-rm -f *.o *.so
