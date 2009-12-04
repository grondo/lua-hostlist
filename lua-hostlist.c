
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#define WITH_LSD_FATAL_ERROR_FUNC
#include "hostlist.h"

static hostlist_t lua_tohostlist (lua_State *L, int index)
{
    hostlist_t *hptr = luaL_checkudata (L, index, "Hostlist");
    return (*hptr);
}

static int push_hostlist (lua_State *L, const char *s)
{
    hostlist_t hl = hostlist_create (s);
    hostlist_t *hlp = lua_newuserdata (L, sizeof (*hlp));

    if (hl == NULL)
        return luaL_error (L, "Unable to create hostlist");

    *hlp = hl;
    luaL_getmetatable (L, "Hostlist");
    lua_setmetatable (L, -2);
    return (1);
}

/*
 *  Push new hostlist on top of stack, return hostlist_t to caller
 */
static hostlist_t lua_hostlist_create (lua_State *L, const char *s)
{
    push_hostlist (L, s);
    return (lua_tohostlist (L, 1));
}

static int l_hostlist_new (lua_State *L)
{
    const char *s = luaL_checkstring (L, 1);
    push_hostlist (L, s);
    /*
     *  Replace string at postion 1 with hostlist now on top
     */
    lua_replace (L, 1);
    return (1);
}

static int l_hostlist_destroy (lua_State *L)
{
    hostlist_t hl = lua_tohostlist (L, 1);
    lua_pop (L, 1);

    hostlist_destroy (hl);
    return (0);
}

static int l_hostlist_nth (lua_State *L)
{
    hostlist_t hl;
    char *host;
    int i = lua_tonumber (L, 2);

    i = lua_tonumber (L, 2);
    lua_pop (L, 1);
    /*
     *  If a string is at the top of stack instead of a hostlist,
     *  try to create a hostlist out of it.
     */
    if (lua_isstring (L, 1))
        l_hostlist_new (L);

    hl = lua_tohostlist (L, 1);
    lua_pop (L, 1);

    if (abs(i) > hostlist_count (hl)) {
        lua_pushnil (L);
        return (1);
    }
    if (i < 0)
        i += hostlist_count (hl) + 1;

    host = hostlist_nth (hl, i-1);

    lua_pushstring (L, host);
    free (host);
    return (1);
}

static int l_hostlist_count (lua_State *L)
{
    hostlist_t hl = lua_tohostlist (L, 1);
    lua_pop (L, 1);
    lua_pushnumber (L, hostlist_count (hl));
    return (1);
}

static int l_hostlist_push (lua_State *L)
{
    hostlist_t hl = lua_tohostlist (L, 1);
    const char *hosts = luaL_checkstring (L, 2);
    lua_pop (L, 2);

    hostlist_push (hl, hosts);
    return (0);
}

static int l_hostlist_pop (lua_State *L)
{
    hostlist_t hl = lua_tohostlist (L, 1);
    int n = lua_tonumber (L, 2);
    int i, t;

    lua_pop (L, 2);

    /*
     *  Create table at position 1 on stack for results of pop
     */
    lua_newtable (L);
    t = lua_gettop (L);

    if (n <= 0 || n >= hostlist_count (hl))
        return luaL_error (L,
                "hostlist.pop: Bad count `%d' for hostlist with %d hosts",
                hostlist_count (hl));

    for (i = 0; i < n; i++) {
        char *host = hostlist_pop (hl);
        if (host == NULL)
            break;
        lua_pushstring (L, host);
        lua_rawseti (L, t, i+1);
        free (host);
    }
    return (1);
}

static int l_hostlist_remove (lua_State *L)
{
    hostlist_t hl = lua_tohostlist (L, 1);
    const char *hosts = luaL_checkstring (L, 2);
    lua_pop (L, 2);

    hostlist_delete (hl, hosts);
    return (0);
}

static int hostlist_remove_list (hostlist_t hl, hostlist_t del)
{
    hostlist_iterator_t i = hostlist_iterator_create (del);
    char *host;

    while ((host = hostlist_next (i))) {
        hostlist_delete_host (hl, host);
        free (host);
    }
    hostlist_iterator_destroy (i);
    return (0);
}

struct hostlist_args {
    int argc;
    unsigned int *created;
    hostlist_t *h;
};

static void lua_hostlist_args_destroy (struct hostlist_args *a)
{
    int i;

    if (a == NULL)
        return;

    if (a->created != NULL && a->h != NULL) {
        for (i = 0; i < a->argc; i++) {
            if (a->created[i])
                hostlist_destroy (a->h[i]);
        }
    }
    if (a->h)
        free (a->h);
    if (a->created)
        free (a->created);
    free (a);
}

/*
 *  Return the top n items from the lua stack promoted to hostlists in h[],
 *   also setting created[i] for each hostlist that was a result of
 *   a hostlist_create() (and thus must be freed).
 */
static struct hostlist_args *lua_hostlist_args_create (lua_State *L)
{
    int i;
    struct hostlist_args *args = malloc (sizeof (*args));

    if (args == NULL)
        return NULL;

    args->argc = lua_gettop (L);

    args->h = malloc (args->argc * sizeof (hostlist_t));
    if (args->h == NULL)
        goto failed;

    args->created = malloc (args->argc * sizeof (int));
    if (args->created == NULL)
        goto failed;

    for (i = 0; i < args->argc; i++) {
        int idx = i + 1;
        if (lua_isuserdata (L, idx)) {
            args->h[i] = lua_tohostlist (L, idx);
            args->created[i] = 0;
        }
        else if (lua_isstring (L, idx)) {
            args->h[i] = hostlist_create (lua_tostring (L, idx));
            if (args->h[i] == NULL)
                goto failed;
            args->created[i] = 1;
        }
    }
    lua_pop (L, args->argc);

    return (args);

 failed:
    lua_hostlist_args_destroy (args);
    return (NULL);
}

static void
hostlist_push_set_result (hostlist_t r, hostlist_t h1,  hostlist_t h2, int xor)
{
    char *host;
    hostlist_iterator_t i = hostlist_iterator_create (h1);

    while ((host = hostlist_next (i))) {
        int found = (hostlist_find (h2, host) >= 0);
        if ((xor && !found) || (!xor && found))
            hostlist_push_host (r, host);
        free (host);
    }
    hostlist_iterator_destroy (i);
}

/*
 *  Perform hostlist intersection or xor (symmetric difference)
 *   against the top two hostlist objects on the stack (promoting
 *   strings to hostlist where necessary).
 */
static int l_hostlist_set_op (lua_State *L, int xor)
{
    hostlist_t r;
    struct hostlist_args *a = lua_hostlist_args_create (L);

    if (a == NULL)
        return luaL_error (L, "Unable to create hostlist");

    r = lua_hostlist_create (L, NULL);

    /*  For now only allow 2 hostlist to be passed to intersection
     *    and xor
     */
    if (a->argc > 2 || a->argc < 1)
        return luaL_error (L, "hostlist set operation require 2 arguments");

    hostlist_push_set_result (r, a->h[0], a->h[1], xor);

    /*
     *  For xor we need to also do reverse order
     */
    if (xor)
        hostlist_push_set_result (r, a->h[1], a->h[0], 1);

    /*
     *  Free any temporary hostlists created in this function:
     */
    lua_hostlist_args_destroy (a);

    /*
     *  Always sort and uniq return hostlist
     */
    hostlist_uniq (r);

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

static int l_hostlist_del (lua_State *L)
{
    hostlist_t r;
    int i;
    struct hostlist_args *a = lua_hostlist_args_create (L);

    if (a == NULL)
        return luaL_error (L, "Unable to create hostlist");

    r = lua_hostlist_create (L, NULL);
    hostlist_push_list (r, a->h[0]);

    for (i = 1; i < a->argc; i++)
        hostlist_remove_list (r, a->h[i]);

    lua_hostlist_args_destroy (a);

    return (1);
}

static int l_hostlist_union (lua_State *L)
{
    hostlist_t r;
    int i;
    struct hostlist_args *a = lua_hostlist_args_create (L);

    if (a == NULL)
        return luaL_error (L, "Unable to create hostlist");

    r = lua_hostlist_create (L, NULL);

    for (i = 0; i < a->argc; i++)
        hostlist_push_list (r, a->h[i]);

    lua_hostlist_args_destroy (a);

    hostlist_uniq (r);

    return (1);
}

static int l_hostlist_tostring (lua_State *L)
{
    char buf [4096];
    hostlist_t hl = lua_tohostlist (L, -1);
    lua_pop (L, 1);
    hostlist_ranged_string (hl, sizeof (buf), buf);

    lua_pushstring (L, buf);
    return (1);
}

static int l_hostlist_concat (lua_State *L)
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
    hostlist_t hl = lua_tohostlist (L, 1);
    hostlist_uniq (hl);
    return (0);
}

static int l_hostlist_sort (lua_State *L)
{
    hostlist_t hl = lua_tohostlist (L, 1);
    hostlist_sort (hl);
    return (0);
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

static int l_hostlist_map (lua_State *L)
{
    char *host;
    hostlist_t hl;
    hostlist_iterator_t i;
    int has_function;
    int n, t, created;

    if (lua_isstring (L, 1)) {
        created = 1;
        hl = hostlist_create (lua_tostring (L, 1));
    }
    else {
        created = 0;
        hl = lua_tohostlist (L, 1);
    }

    if (hl == NULL)
        return luaL_error (L, "Unable to create hostlist");

    has_function = lua_isfunction (L, 2);

    /*  Create new table at top of stack to hold results:
     */
    lua_newtable (L);
    t = lua_gettop (L);

    n = 1;
    i = hostlist_iterator_create (hl);
    while ((host = hostlist_next (i))) {
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
        if (has_function && lua_pcall (L, 1, 1, 0) != 0) {
                hostlist_iterator_destroy (i);
                free (host);
                return luaL_error (L, "map: %s", lua_tostring (L, -1));
        }

        /*
         *  Only push entry on table if there was a return value
         */
        if (lua_isnil (L, -1))
            lua_pop (L, 1);
        else
            lua_rawseti (L, t, n++);
        free (host);
    }

    hostlist_iterator_destroy(i);
    if (created)
        hostlist_destroy (hl);

    /*  Clean up stack and return
     */
    lua_replace (L, 1);
    lua_pop (L, lua_gettop (L) - 1);

    return (1);
}


/*
 *  Return a hostlist_iterator_t *  full userdata as hostlist_iterator_t
 */
static hostlist_iterator_t lua_tohostlist_iterator (lua_State *L, int index)
{
    hostlist_iterator_t *ip = luaL_checkudata (L, index, "HostlistIterator");
    return (*ip);
}


static int l_hostlist_iterator_destroy (lua_State *L)
{
    hostlist_iterator_t i = lua_tohostlist_iterator (L, 1);
    hostlist_iterator_destroy (i);
    return (0);
}

/*
 *  Hostlist iterator function (assumed to be a C closure)
 */
static int l_hostlist_iterator (lua_State *L)
{
    char *host;
    /*
     *  Get hostlist iterator instance, which is the sole upvalue
     *   for this closure
     */
    int index = lua_upvalueindex (1);
    hostlist_iterator_t i = lua_tohostlist_iterator (L, index);

    if (i == NULL)
        return luaL_error (L, "Invalid hostlist iterator");

    host = hostlist_next (i);
    if (host != NULL) {
        lua_pushstring (L, host);
        free (host);
        return (1);
    }
    return (0);
}

/*
 *  Create a new iterator (as a C closure)
 */
static int l_hostlist_next (lua_State *L)
{
    hostlist_t hl = lua_tohostlist (L, 1);
    hostlist_iterator_t *ip;

    lua_pop (L, 1);

    /*
     *  Push hostlist iterator onto stack top with metatable set
     */
    ip = lua_newuserdata (L, sizeof (*ip));
    *ip = hostlist_iterator_create (hl);
    luaL_getmetatable (L, "HostlistIterator");
    lua_setmetatable (L, -2);


    /*
     *  Used in for loop, iterator creation function should return:
     *   iterator, state, starting val (nil)
     *    state is nil becuase we are using a closure.
     */
    lua_pushcclosure (L, l_hostlist_iterator, 1);

    return (1);
}

static const struct luaL_Reg hostlist_functions [] = {
    { "new",        l_hostlist_new       },
    { "intersect",  l_hostlist_intersect },
    { "xor",        l_hostlist_xor       },
    { "delete",     l_hostlist_del       },
    { "union",      l_hostlist_union     },
    { "map",        l_hostlist_map       },
    { "nth",        l_hostlist_nth       },
    { "pop",        l_hostlist_pop       },
    { NULL,         NULL                 }
};

static const struct luaL_Reg hostlist_methods [] = {
    { "__len",      l_hostlist_count     },
    { "__index",    l_hostlist_index     },
    { "__tostring", l_hostlist_tostring  },
    { "__concat",   l_hostlist_concat    },
    { "__add",      l_hostlist_union     },
    { "__mul",      l_hostlist_intersect },
    { "__pow",      l_hostlist_xor       },
    { "__sub",      l_hostlist_del       },
    { "__gc",       l_hostlist_destroy   },
    { "delete",     l_hostlist_remove    },
    { "append",     l_hostlist_push      },
    { "uniq",       l_hostlist_uniq      },
    { "sort",       l_hostlist_sort      },
    { "next",       l_hostlist_next      },
    { "map",        l_hostlist_map       },
    { "pop",        l_hostlist_pop       },
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

int luaopen_hostlist (lua_State *L)
{
	luaL_newmetatable (L, "Hostlist");

    /*  Register hostlist methods in metatable */
    luaL_register (L, NULL, hostlist_methods);

    luaL_newmetatable (L, "HostlistIterator");
    luaL_register (L, NULL, hostlist_iterator_methods);

    /*  Register hostlist public table functions: */
	luaL_register (L, "hostlist", hostlist_functions);

    return 1;
}

/*
 * vi: ts=4 sw=4 expandtab
 */
