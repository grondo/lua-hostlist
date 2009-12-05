
all: hostlist.so

hostlist_OBJS = hostlist.o lua-hostlist.o

.SUFFIXES: .c .o .so

.c.o:
	$(CC) -fPIC -g -Wall -c $<

hostlist.so: $(hostlist_OBJS)
	$(CC) -shared -o $*.so $^ $(LDFLAGS) $(LIBS)

check: hostlist.so
	@(cd tests && LUA_CPATH=../?.so ./lunit tests.lua)

clean:
	-rm -f *.o *.so
