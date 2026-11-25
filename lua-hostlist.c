/************************************************************\
 * Copyright 2013 Lawrence Livermore National Security, LLC
 * (c.f. NOTICE.LLNS, LICENSE)
 *
 * This file is part of lua-hostlist.
 * For details, see https://github.com/grondo/lua-hostlist.
 *
 * SPDX-License-Identifier: LGPL-3.0
\************************************************************/

/*  lua-hostlist.c - Lua bindings for flux-core libhostlist
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include "src/common/libhostlist/hostlist.h"

/*############################################################################
 *
 *  Hostlist Lua stack utility functions:
 *
 *##########################################################################*/

/*
 *  Return the hostlist object at index in the Lua stack, or error
 *   and abort.
 */
static struct hostlist *lua_tohostlist (lua_State *L, int index)
{
    struct hostlist **hptr = luaL_checkudata (L, index, "Hostlist");
    return (*hptr);
}

/*
 *  Push hostlist hl as userdata onto the Lua stack with its metatable set.
 */
static int push_hostlist_userdata (lua_State *L, struct hostlist *hl)
{
    struct hostlist **hlp = lua_newuserdata (L, sizeof (*hlp));

    *hlp = hl;
    luaL_getmetatable (L, "Hostlist");
    lua_setmetatable (L, -2);
    return (1);
}

/*
 *  Create a new hostlist from string `s' and push it onto the top
 *   of the Lua stack as userdata.
 */
static int push_hostlist (lua_State *L, const char *s)
{
    struct hostlist *hl = s ? hostlist_decode (s) : hostlist_create ();
    if (hl == NULL)
        return luaL_error (L, "Unable to create hostlist");

    return push_hostlist_userdata (L, hl);
}

/*
 *  Just like `push_hostlist' above, but return the new hostlist
 *   to the caller.
 */
static struct hostlist *lua_hostlist_create (lua_State *L, const char *s)
{
    push_hostlist (L, s);
    return (lua_tohostlist (L, -1));
}

/*
 *  Replace a string at index in the Lua stack with a hostlist
 *   If index is already a hostlist, just return a reference to
 *   that object.
 *
 *  Note that the caller does not need to free the returned hostlist.
 *   The Lua garbage collector will handle this.
 */
static struct hostlist *lua_string_to_hostlist (lua_State *L, int index)
{
    const char *s;
    struct hostlist *hl;

    if (lua_isuserdata (L, index))
        return lua_tohostlist (L, index);

    /*
     *  Create a new hostlist on top of stack
     */
    s = luaL_checkstring (L, index);
    hl = lua_hostlist_create (L, s);

    /*
     *  Replace the string at index with this hostlist
     */
    lua_replace (L, index);
    return (hl);
}

/*
 *  Push a copy of hostlist at index onto the top of the Lua stack and
 *   return it. The copy is owned by the Lua garbage collector.
 *
 *  hostlist iteration uses a cursor internal to the hostlist object,
 *   so a private copy should be used for any traversal during which
 *   the original hostlist may be accessed or modified (e.g. when
 *   calling back into Lua, or when the hostlist is also the target
 *   of the operation).
 */
static struct hostlist *lua_hostlist_copy (lua_State *L, int index)
{
    struct hostlist *hl = hostlist_copy (lua_tohostlist (L, index));
    if (hl == NULL)
        luaL_error (L, "Unable to copy hostlist");
    push_hostlist_userdata (L, hl);
    return (hl);
}

/*
 *  Remove up to [limit] occurrences (limit <= 0 implies unlimited)
 *   of each host in hostlist [del] from hostlist [hl].
 *
 *  hl and del must not be the same hostlist.
 */
static int hostlist_remove_list (struct hostlist *hl,
                                 struct hostlist *del,
                                 int limit)
{
    const char *host;

    for (host = hostlist_first (del); host; host = hostlist_next (del)) {
        /*
         *  Delete up to limit occurrences of host in list (0 == unlimited)
         */
        int n = limit;
        /* If n == 0 then (--n) should never evaluate true */
        while (hostlist_find (hl, host) >= 0
               && hostlist_remove_current (hl) > 0
               && --n) {;}
    }
    return (0);
}

/*
 *  Remove hosts in hostlist at index [del] from hostlist at index [hl],
 *   making a copy of [del] if it refers to the same hostlist as [hl].
 */
static int lua_hostlist_remove_list (lua_State *L, int hl, int del, int limit)
{
    struct hostlist *h = lua_tohostlist (L, hl);
    struct hostlist *d = lua_tohostlist (L, del);

    if (h == d) {
        d = lua_hostlist_copy (L, del);
        hostlist_remove_list (h, d, limit);
        lua_pop (L, 1);
    }
    else
        hostlist_remove_list (h, d, limit);
    return (0);
}


/*############################################################################
 *
 *  Hostlist library methods:
 *
 *##########################################################################*/

static int l_hostlist_new (lua_State *L)
{
    int i;
    int argc = lua_gettop (L);
    struct hostlist *hl;

    /*
     *  Create a hostlist from the first argument, or an empty
     *   hostlist if there are no arguments or the first is nil.
     */
    hl = lua_hostlist_create (L, lua_tostring (L, 1));

    /*
     *  Append any remaining arguments
     */
    for (i = 2; i <= argc; i++) {
        if (lua_isuserdata (L, i)) {
            if (hostlist_append_list (hl, lua_tohostlist (L, i)) < 0)
                return luaL_error (L, "Unable to append hostlist");
        }
        else if (hostlist_append (hl, luaL_checkstring (L, i)) < 0)
            return luaL_error (L, "Unable to create hostlist");
    }
    return (1);
}

/*
 *  This is the hostlist userdata garbage collector method:
 */
static int l_hostlist_destroy (lua_State *L)
{
    struct hostlist *hl = lua_tohostlist (L, 1);
    lua_pop (L, 1);
    hostlist_destroy (hl);
    return (0);
}

static int l_hostlist_nth (lua_State *L)
{
    struct hostlist *hl;
    const char *host;
    int i = lua_tonumber (L, 2);

    /*
     *  If a string is at index 1 instead of a hostlist,
     *  try to create a hostlist out of it.
     */
    hl = lua_string_to_hostlist (L, 1);

    /*
     *  If index == 0 or is outside of the range of this hostlist,
     *   return nil
     */
    if ((i == 0) || (abs(i) > hostlist_count (hl))) {
        lua_pushnil (L);
        return (1);
    }

    /*
     *  -i indexes from end of list
     */
    if (i < 0)
        i += hostlist_count (hl) + 1;

    host = hostlist_nth (hl, i-1);

    lua_pushstring (L, host);
    return (1);
}

static int l_hostlist_count (lua_State *L)
{
    struct hostlist *hl = lua_string_to_hostlist (L, 1);
    lua_pop (L, 1);
    lua_pushinteger (L, hostlist_count (hl));
    return (1);
}

static int l_hostlist_pop (lua_State *L)
{
    struct hostlist *hl = lua_tohostlist (L, 1);
    int shift = 0;
    int n = 1;
    int i, t;

    if (lua_gettop (L) > 2)
        return luaL_error (L,
                "Expected 2 arguments to hostlist.pop (got %d)",
                lua_gettop (L));

    if (lua_isnumber (L, 2))
        n = lua_tonumber (L, 2);

    /*
     *  Create table on top of stack for results of pop
     */
    lua_newtable (L);
    t = lua_gettop (L);

    if (n < 0) {
        shift = 1;
        n = abs(n);
    }

    for (i = 0; i < n; i++) {
        const char *host;
        if (shift)
            host = hostlist_first (hl);
        else
            host = hostlist_last (hl);
        if (host == NULL)
            break;
        lua_pushstring (L, host);
        lua_rawseti (L, t, i+1);
        hostlist_remove_current (hl);
    }
    return (1);
}


static int l_hostlist_remove_n (lua_State *L)
{
    int limit = 0;

    lua_string_to_hostlist (L, 1);
    lua_string_to_hostlist (L, 2);

    /*
     *  Check for a numeric 3rd argument, which is the
     *   total number of entries to delete (in case there are
     *   duplicate hosts in the hostlist).
     */
    if (lua_gettop (L) == 3)
        limit = luaL_checknumber (L, 3);

    lua_hostlist_remove_list (L, 1, 2, limit);

    /*
     *  Return a reference to the original hostlist
     */
    lua_settop (L, 1);
    return (1);
}

/*
 *  As above, but takes variable number of args,
 *   always remove all hosts
 */
static int l_hostlist_remove (lua_State *L)
{
    int argc = lua_gettop (L);
    int i;

    lua_string_to_hostlist (L, 1);

    for (i = 2; i < argc+1; i++) {
        lua_string_to_hostlist (L, i);
        lua_hostlist_remove_list (L, 1, i, 0);
    }

    /*  Remove all args but the hostlist
     */
    lua_settop (L, 1);
    return (1);
}

static int l_hostlist_find (lua_State *L)
{
    struct hostlist *hl;
    const char *host;
    int found;

    /*
     *   hostlist.find (hostlist, hostname)
     */
    hl = lua_string_to_hostlist (L, 1);
    host = luaL_checkstring (L, 2);

    found = hostlist_find (hl, host);
    lua_pop (L, 2);

    /*
     *  Return nil if hostlist not found, otherwise return
     *   the index of the first match. (Remember: lua index starts
     *   from 1 not 0.
     */
    if (found < 0)
        lua_pushnil (L);
    else
        lua_pushinteger (L, found+1);

    return (1);
}

static int l_hostlist_concat (lua_State *L)
{
    struct hostlist *hl = lua_string_to_hostlist (L, 1);
    int i;
    int argc = lua_gettop (L);

    for (i = 2; i < argc+1; i++) {
        if (lua_isuserdata (L, i))
            hostlist_append_list (hl, lua_tohostlist (L, i));
        else
            hostlist_append (hl, luaL_checkstring (L, i));
    }

    /*
     *  Clean up stack and return original hostlist
     */
    lua_settop (L, 1);
    return (1);
}

/*
 *  Core function for Intersect and XOR
 */
static void
hostlist_push_set_result (struct hostlist *r,
                          struct hostlist *h1,
                          struct hostlist *h2,
                          int xor)
{
    const char *host;

    for (host = hostlist_first (h1); host; host = hostlist_next (h1)) {
        int found = (hostlist_find (h2, host) >= 0);
        if ((xor && !found) || (!xor && found))
            hostlist_append (r, host);
    }
}

/*
 *  Perform hostlist intersection or xor (symmetric difference)
 *   against the top two hostlist objects on the stack (promoting
 *   strings to hostlist where necessary).
 */
static int l_hostlist_set_op (lua_State *L, int xor)
{
    int i;
    struct hostlist *r;
    int nargs = lua_gettop (L);

    /*
     *  Create hostlist to hold result and push first arg
     */
    r = hostlist_create ();
    hostlist_append_list (r, lua_string_to_hostlist (L, 1));

    /*
     *  Now incrementally build results in r for each arg (2..n)
     */
    for (i = 2; i <= nargs ; i++) {
        struct hostlist *hl = lua_string_to_hostlist (L, i);
        struct hostlist *tmp = hostlist_create ();

        hostlist_push_set_result (tmp, r, hl, xor);

        /*
         *  For xor we need to also do reverse order
         */
        if (xor)
            hostlist_push_set_result (tmp, hl, r, xor);

        /*
         *   tmp is the new r
         */
        hostlist_destroy (r);
        r = tmp;
    }

    /*
     *  Always sort and uniq return hostlist
     */
    hostlist_uniq (r);
    push_hostlist_userdata (L, r);
    return (1);
}


static int l_hostlist_intersect (lua_State *L)
{
    return l_hostlist_set_op (L, 0);
}
static int l_hostlist_xor (lua_State *L)
{
    return l_hostlist_set_op (L, 1);
}


/*
 *  hostlist_del: delete all occurrences of hosts from first argument
 *   Returns a new hostlist object and doesn't modify the first arg
 */
static int l_hostlist_del (lua_State *L)
{
    struct hostlist *r;
    int i;
    int nargs = lua_gettop (L);

    /*
     *   del = (((hl1 - hl2) - hl3) - ... )
     *
     *   Start with first list and remove all others
     */
    r = hostlist_create ();
    hostlist_append_list (r, lua_string_to_hostlist (L, 1));

    for (i = 2; i <= nargs; i++)
        hostlist_remove_list (r, lua_string_to_hostlist (L, i), 0);

    push_hostlist_userdata (L, r);
    return (1);
}

static int l_hostlist_union (lua_State *L)
{
    struct hostlist *r;
    int i;
    int nargs = lua_gettop (L);

    r = hostlist_create ();

    for (i = 1; i <= nargs; i++)
        hostlist_append_list (r, lua_string_to_hostlist (L, i));

    hostlist_uniq (r);
    push_hostlist_userdata (L, r);

    return (1);
}

static int l_hostlist_tostring (lua_State *L)
{
    char *s;
    struct hostlist *hl = lua_tohostlist (L, -1);

    if (!(s = hostlist_encode (hl)))
        return luaL_error (L, "Unable to encode hostlist");
    lua_pop (L, 1);
    lua_pushstring (L, s);
    free (s);
    return (1);
}

static int l_hostlist_strconcat (lua_State *L)
{
    const char *s;

    if (lua_isuserdata (L, 1)) {
        /*  Remove string (2nd arg) from stack, leaving hostlist on top:
         */
        s = lua_tostring (L, 2);
        lua_pop (L, 1);

        /*  Convert hostlist to string and leave on stack:
         */
        l_hostlist_tostring (L);

        /*  Push string back into 2nd position
         */
        lua_pushstring (L, s);
    }
    else if (lua_isuserdata (L, 2)) {
        /*  If hostlist is already at top of stack, just convert in place
         */
        l_hostlist_tostring (L);
    }

    /*  Now simply concat the two strings at the top of the stack
     *   and return the result.
     */
    lua_concat (L, 2);
    return (1);
}

static int l_hostlist_uniq (lua_State *L)
{
    struct hostlist *hl = lua_tohostlist (L, 1);
    hostlist_uniq (hl);
    /*
     *  Return a reference to the hostlist
     */
    return (1);
}

static int l_hostlist_sort (lua_State *L)
{
    struct hostlist *hl = lua_tohostlist (L, 1);
    hostlist_sort (hl);
    /*
     *  Return a reference to the hostlist
     */
    return (1);
}

static int l_hostlist_index (lua_State *L)
{
    const char *key = lua_tostring (L, 2);

    if (key == NULL)
        return luaL_error (L, "hostlist: invalid index");

    /*
     *  Check to see if key is a name of a method in the metatable
     *   and return the method if so:
     *
     *  [ Lua will first try to resolve unknown table entries from hostlist
     *     object using __index in the object's metatable. The __index
     *     function should then return the method in question, which is
     *     then called with the supplied arguments. (Thus we can't directly
     *     call the named method here, instead we leave the method reference
     *     on the stack as a cfunction. Normally, if you are not trying to
     *     overload the [] operator, you can assign the metatable's __index
     *     to the metatable itself to get the same effect.) ]
     */
    lua_getmetatable (L, 1);
    lua_getfield (L, -1, key);
    if (!lua_isnil (L, -1))
        return 1;

    /*
     *  Else hl[n] was requested, so return the nth host.
     */
    return (l_hostlist_nth (L));
}

/*
 *  Map a function across all members of a hostlist.
 *   Returns a hostlist. Function argument is required.
 */
static int l_hostlist_map (lua_State *L)
{
    const char *host;
    struct hostlist *hl, *r;

    lua_string_to_hostlist (L, 1);
    if (!lua_isfunction (L, 2))
        return luaL_argerror (L, 2, "expected function argument");
    lua_settop (L, 2);

    /*  Iterate over a copy of the hostlist, since the function may
     *   access or modify the original.
     */
    hl = lua_hostlist_copy (L, 1);

    /*  Create new hostlist at top of stack to hold results:
     */
    r = lua_hostlist_create (L, NULL);

    for (host = hostlist_first (hl); host; host = hostlist_next (hl)) {
        /*  Copy function to run to top of stack to be consumed by lua_pcall
         */
        lua_pushvalue (L, 2);

        /*  Push hostname for arg to fn:
         */
        lua_pushstring (L, host);

        /*
         *  Call function and leave 1 result on the stack
         */
        if (lua_pcall (L, 1, 1, 0) != 0)
                return luaL_error (L, "map: %s", lua_tostring (L, -1));

        /*
         *  Only push entry on hostlist if there was a return value
         */
        if (!lua_isnil (L, -1))
            hostlist_append (r, lua_tostring (L, -1));
        lua_pop (L, 1);
    }

    /*  Clean up stack and return
     */
    lua_replace (L, 1);
    lua_settop (L, 1);

    return (1);
}

/*
 *  Return a hostlist as a lua table, optionally applying a function
 *   argument to all hosts.
 */
static int l_hostlist_expand (lua_State *L)
{
    const char *host;
    struct hostlist *hl;
    int has_function;
    int n, t;

    lua_string_to_hostlist (L, 1);

    has_function = lua_isfunction (L, 2);
    lua_settop (L, 2);

    /*  Iterate over a copy of the hostlist, since the function may
     *   access or modify the original.
     */
    hl = lua_hostlist_copy (L, 1);

    /*  Create new table at top of stack to hold results:
     */
    lua_newtable (L);
    t = lua_gettop (L);

    n = 1;
    for (host = hostlist_first (hl); host; host = hostlist_next (hl)) {
        /*  If we have a function to run, copy onto the top of the stack
         *   to be consumed by lua_pcall
         */
        if (has_function)
            lua_pushvalue (L, 2);

        /*  Push hostname, either as value for the table, or arg to fn:
         */
        lua_pushstring (L, host);

        /*
         *  Call function if needed and leave 1 result on the stack
         */
        if (has_function && lua_pcall (L, 1, 1, 0) != 0)
                return luaL_error (L, "map: %s", lua_tostring (L, -1));

        /*
         *  Only push entry on table if there was a return value
         */
        if (lua_isnil (L, -1))
            lua_pop (L, 1);
        else
            lua_rawseti (L, t, n++);
    }

    /*  Clean up stack and return
     */
    lua_replace (L, 1);
    lua_settop (L, 1);

    return (1);
}


/*
 *  Hostlist iterator state, stored as full userdata.
 *
 *  The iterator holds a private copy of the hostlist so that iteration
 *   is unaffected by any access to (and modification of) the original
 *   hostlist, and so that the iterator remains valid even if the
 *   original hostlist is garbage collected.
 */
struct hostlist_iterator {
    struct hostlist *hl;
    int started;
};

static struct hostlist_iterator *
lua_tohostlist_iterator (lua_State *L, int index)
{
    return luaL_checkudata (L, index, "HostlistIterator");
}


static int l_hostlist_iterator_destroy (lua_State *L)
{
    struct hostlist_iterator *i = lua_tohostlist_iterator (L, 1);
    hostlist_destroy (i->hl);
    i->hl = NULL;
    return (0);
}

/*
 *  Hostlist iterator function (assumed to be a C closure)
 */
static int l_hostlist_iterator (lua_State *L)
{
    const char *host;
    /*
     *  Get hostlist iterator instance, which is the sole upvalue
     *   for this closure
     */
    int index = lua_upvalueindex (1);
    struct hostlist_iterator *i = lua_tohostlist_iterator (L, index);

    if (i->hl == NULL)
        return luaL_error (L, "Invalid hostlist iterator");

    if (!i->started) {
        i->started = 1;
        host = hostlist_first (i->hl);
    }
    else
        host = hostlist_next (i->hl);

    if (host != NULL) {
        lua_pushstring (L, host);
        return (1);
    }
    return (0);
}

/*
 *  Create a new iterator (as a C closure)
 */
static int l_hostlist_next (lua_State *L)
{
    struct hostlist *hl = lua_tohostlist (L, 1);
    struct hostlist_iterator *i;

    /*
     *  Push hostlist iterator onto stack top with metatable set
     */
    i = lua_newuserdata (L, sizeof (*i));
    i->hl = NULL;
    i->started = 0;
    luaL_getmetatable (L, "HostlistIterator");
    lua_setmetatable (L, -2);

    if (!(i->hl = hostlist_copy (hl)))
        return luaL_error (L, "Unable to create hostlist iterator");

    /*
     *  Used in for loop, iterator creation function should return:
     *   iterator, state, starting val (nil)
     *    state is nil because we are using a closure.
     */
    lua_pushcclosure (L, l_hostlist_iterator, 1);

    return (1);
}

/*############################################################################
 *
 *  Hostlist interface definitions and initialization:
 *
 *##########################################################################*/

static const struct luaL_Reg hostlist_functions [] = {
    { "new",        l_hostlist_new       },
    { "intersect",  l_hostlist_intersect },
    { "xor",        l_hostlist_xor       },
    { "delete",     l_hostlist_remove    },
    { "delete_n",   l_hostlist_remove_n  },
    { "union",      l_hostlist_union     },
    { "map",        l_hostlist_map       },
    { "expand",     l_hostlist_expand    },
    { "nth",        l_hostlist_nth       },
    { "pop",        l_hostlist_pop       },
    { "concat",     l_hostlist_concat    },
    { "find",       l_hostlist_find      },
    { "count",      l_hostlist_count     },
    { NULL,         NULL                 }
};

static const struct luaL_Reg hostlist_methods [] = {
    { "__len",      l_hostlist_count     },
    { "__index",    l_hostlist_index     },
    { "__tostring", l_hostlist_tostring  },
    { "__concat",   l_hostlist_strconcat },
    { "__add",      l_hostlist_union     },
    { "__mul",      l_hostlist_intersect },
    { "__pow",      l_hostlist_xor       },
    { "__sub",      l_hostlist_del       },
    { "__gc",       l_hostlist_destroy   },
    { "count",      l_hostlist_count     },
    { "delete",     l_hostlist_remove    },
    { "delete_n",   l_hostlist_remove_n  },
    { "concat",     l_hostlist_concat    },
    { "uniq",       l_hostlist_uniq      },
    { "sort",       l_hostlist_sort      },
    { "next",       l_hostlist_next      },
    { "map",        l_hostlist_map       },
    { "expand",     l_hostlist_expand    },
    { "pop",        l_hostlist_pop       },
    { "find",       l_hostlist_find      },
    { NULL,         NULL                 }
};


/*
 *  Hostlist iterator only needs a garbage collection method,
 *   it is not otherwise exposed to Lua scripts.
 */
static const struct luaL_Reg hostlist_iterator_methods [] = {
    { "__gc",       l_hostlist_iterator_destroy   },
    { NULL,         NULL                          }
};


#if !defined LUA_VERSION_NUM || LUA_VERSION_NUM==501
/*
** Adapted from Lua 5.2.0
*/
static void luaL_setfuncs (lua_State *L, const luaL_Reg *l, int nup) {
    luaL_checkstack(L, nup+1, "too many upvalues");
    for (; l->name != NULL; l++) {  /* fill the table with given functions */
        int i;
        lua_pushstring(L, l->name);
        for (i = 0; i < nup; i++)  /* copy upvalues to the top */
            lua_pushvalue(L, -(nup+1));
        lua_pushcclosure(L, l->func, nup);  /* closure with those upvalues */
        lua_settable(L, -(nup + 3));
    }
    lua_pop(L, nup);  /* remove upvalues */
}
#endif

int luaopen_hostlist (lua_State *L)
{
    luaL_newmetatable (L, "Hostlist");
    /*  Register hostlist methods in metatable */
    luaL_setfuncs (L, hostlist_methods, 0);

    luaL_newmetatable (L, "HostlistIterator");
    luaL_setfuncs (L, hostlist_iterator_methods, 0);

    /*  Register hostlist public table functions: */
    lua_newtable (L);
    luaL_setfuncs (L, hostlist_functions, 0);

    return 1;
}

/*
 * vi: ts=4 sw=4 expandtab
 */
