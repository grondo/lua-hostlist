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
--   If `input' is set, it is written to the stdin of hostlist.
--   The exit status is appended to stdout by the shell, since in
--   Lua 5.1 closing a popen file does not return the exit status.
local input

local function hostlist (...)
	local args = {}
	for i, a in ipairs ({...}) do
		args[i] = shell_quote (a)
	end
	local cmd = string.format ("%s -e %s ./hostlist %s <%s 2>%s; echo $?",
		lua,
		shell_quote ('package.cpath="./?.so;"..package.cpath'),
		table.concat (args, " "),
		input and "/dev/stdin" or "/dev/null",
		tmpfile)
	if input then
		cmd = "printf %s " .. shell_quote (input) .. " | (" .. cmd .. ")"
	end
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

function test_deprecated_options_warn()
	local out, err, ok = hostlist ("-R", "1", "foo[1,1,2]", "foo1")
	luaunit.assertTrue (ok)
	luaunit.assertEquals (out, "foo[1-2]\n")
	luaunit.assertStrContains (err, "-R, --remove is deprecated")

	out, err, ok = hostlist ("--filter=s:upper()", "foo[1-3]")
	luaunit.assertTrue (ok)
	luaunit.assertEquals (out, "FOO[1-3]\n")
	luaunit.assertStrContains (err, "-f, --filter is deprecated")
end

function test_no_warning_by_default()
	for _, args in ipairs {
		{ "foo[1-3]" },
		{ "-e", "foo[1-3]" },
		{ "-c", "foo[1-3]" },
		{ "-m", "foo[1-3]", "foo2" },
	} do
		local _, err, ok = hostlist (unpack (args))
		luaunit.assertTrue (ok)
		luaunit.assertEquals (err, "")
	end
end

function test_flux_hostlist_aliases()
	for _, t in ipairs {
		{ args = { "-L", "3", "foo[1-10]" },                 result = "foo[1-3]" },
		{ args = { "--limit=-3", "foo[1-10]" },              result = "foo[8-10]" },
		{ args = { "-s", "3", "foo[1-10]" },                 result = "foo[1-3]" },
		{ args = { "--intersect", "foo[1-5]", "foo[4-10]" }, result = "foo[4-5]" },
		{ args = { "--intersection", "foo[1-5]", "foo[4-10]" }, result = "foo[4-5]" },
		{ args = { "--delimiter=:", "-e", "foo[1-3]" },      result = "foo1:foo2:foo3" },
		{ args = { "--delimiters=:", "-e", "foo[1-3]" },     result = "foo1:foo2:foo3" },
	} do
		local out, err, ok = hostlist (unpack (t.args))
		luaunit.assertTrue (ok)
		luaunit.assertEquals (out, t.result .. "\n")
		luaunit.assertEquals (err, "")
	end
end

function test_empty_input()
	for _, s in ipairs { "", "\n", "  \t \n\n" } do
		input = s
		for _, args in ipairs {
			{}, { "-c" }, { "-e" }, { "-u" }, { "-i" }, { "-X" },
			{ "-x" }, { "-m" }, { "-R", "1" }, { "-S" }, { "-q" },
			{ "-n", "1" }, { "-F", "foo1" },
		} do
			local out, err, ok = hostlist (unpack (args))
			local desc = string.format ("%q with args %s",
				s, table.concat (args, " "))
			luaunit.assertFalse (ok, desc)
			luaunit.assertEquals (out, "", desc)
			luaunit.assertNotStrContains (err, "stack traceback", desc)
		end
	end
	input = nil

	--  Input from stdin still works
	input = "foo1 foo2\n foo3\n"
	local out, _, ok = hostlist ()
	luaunit.assertTrue (ok)
	luaunit.assertEquals (out, "foo[1-3]\n")
	input = nil
end

local rc = luaunit.LuaUnit.run ()
os.remove (tmpfile)
os.exit (rc)
