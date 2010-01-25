
LUA_VER ?=     5.1
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
	install -D -m0655 hostlist $(DESTDIR)$(PREFIX)/bin/hostlist

clean:
	-rm -f *.o *.so
