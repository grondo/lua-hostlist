--------------------------------------------------------------
-- Copyright 2026 Lawrence Livermore National Security, LLC
-- (c.f. NOTICE.LLNS, LICENSE)
--
-- This file is part of lua-hostlist.
-- For details, see https://github.com/grondo/lua-hostlist.
--
-- SPDX-License-Identifier: LGPL-3.0
--------------------------------------------------------------
--
--  Tests for the hostlist command line utility
--

local luaunit = require 'luaunit'

local unpack = table.unpack or unpack

--  Run the hostlist utility from the top of the source tree with the
--   same Lua interpreter running these tests, using the hostlist.so
--   module built in the source tree.
--
local lua = arg[-1] or "lua"
local tmpfile = os.tmpname ()

local function shell_quote (s)
	return "'" .. s:gsub ("'", "'\\''") .. "'"
end

--  Run hostlist with args and return stdout, stderr, and success.
--   The exit status is appended to stdout by the shell, since in
--   Lua 5.1 closing a popen file does not return the exit status.
local function hostlist (...)
	local args = {}
	for i, a in ipairs ({...}) do
		args[i] = shell_quote (a)
	end
	local cmd = string.format ("%s -e %s ./hostlist %s 2>%s; echo $?",
		lua,
		shell_quote ('package.cpath="./?.so;"..package.cpath'),
		table.concat (args, " "),
		tmpfile)
	local f = io.popen (cmd)
	local out = f:read ("*a")
	f:close ()
	local status
	out, status = out:match ("^(.-)(%d+)\n$")
	local ef = io.open (tmpfile)
	local err = ef:read ("*a")
	ef:close ()
	return out, err, tonumber (status) == 0
end

function test_remove_long_option()
	for _, args in ipairs {
		{ "-R", "1" },
		{ "--remove=1" },
		{ "--remove", "1" },
	} do
		table.insert (args, "foo[1,1,2]")
		table.insert (args, "foo1")
		local out, _, ok = hostlist (unpack (args))
		luaunit.assertTrue (ok)
		luaunit.assertEquals (out, "foo[1-2]\n")
	end
end

local rc = luaunit.LuaUnit.run ()
os.remove (tmpfile)
os.exit (rc)
