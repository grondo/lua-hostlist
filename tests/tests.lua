--[[#######################################################################
 #
 # Unit tests for lua hostlist implementation
 #
--#########################################################################
 #  Copyright (C) 2013, Lawrence Livermore National Security, LLC.
 #  Produced at Lawrence Livermore National Laboratory (cf, DISCLAIMER).
 #  Written by Mark Grondona <mgrondona@llnl.gov>
 #
 #  LLNL-CODE-645467 All Rights Reserved.
 #
 #  This file is part of lua-hostlist.
 #
 #  This program is free software; you can redistribute it and/or modify it
 #  under the terms of the GNU General Public License (as published by the
 #  Free Software Foundation) version 2, dated June 1991.
 #
 #  This program is distributed in the hope that it will be useful, but
 #  WITHOUT ANY WARRANTY; without even the IMPLIED WARRANTY OF MERCHANTABILITY
 #  or FITNESS FOR A PARTICULAR PURPOSE. See the terms and conditions of the
 #  GNU General Public License for more details.
 #
 #  You should have received a copy of the GNU General Public License along
 #  with SLURM; if not, write to the Free Software Foundation, Inc.,
 #  59 Temple Place, Suite 330, Boston, MA  02111-1307  USA.
--#########################################################################--]]


local luaunit = require 'luaunit'
local hostlist = require 'hostlist'

if _VERSION >= 'Lua 5.2' then
    unpack = table.unpack
    loadstring = load
end

TestHostlist = {

	to_string = {
		["1,2,3,5,6"] =      "[1-3,5-6]"
	},

	expand = {
		["foo[1-5]"] =       "foo1,foo2,foo3,foo4,foo5",
		["foo[0-4]-eth2"] =  "foo0-eth2,foo1-eth2,foo2-eth2,foo3-eth2,foo4-eth2",
		["foo1,foo1,foo1"] = "foo1,foo1,foo1",
		["[00-02]"] = "00,01,02",
	},

	counts = {
		["foo[1,1,1]"] = 3,
		["foo[1-100]"] = 100,
		[""] = 0,
	},

	indeces = {
		{ hl="foo[1-100]",  index=50,        result="foo50"            },
		{ hl="foo[0-100]",  index=50,        result="foo49"            },
	},

	delete = {
		{ hl="foo[1-5]",       args={"foo3"},     result="foo[1-2,4-5]"     },
		{ hl="foo[1,2,1]",     args={"foo1"},     result="foo2"             },
		{ hl="foo[1,1,1]",     args={"foo1"},     result=""                 },
		{ hl="foo[2-5],fooi",  args={"foo[1-2]"}, result="foo[3-5],fooi"    },
		{ hl="[99-105]",       args={"101"},      result="[99-100,102-105]" },
		{ hl="[099-105]",      args={"101"},      result="[099-100,102-105]" },
		{ hl="foo[1-10]",      args={"foo[1-2]","foo3","foo10"},
			                 result="foo[4-9]" },

	},

	["delete_n"] = {
		{ hl="foo[1,1,2,1]",  delete="foo1",   n=1, result="foo[1-2,1]"      },
		{ hl="foo[1,1,2,1]",  delete="foo1",   n=2, result="foo[2,1]"        },
		{ hl="foo[1,1,2,1]",  delete="foo1",   n=3, result="foo2"            },
		{ hl="foo[1,1,2,1]",  delete="foo1",   n=0, result="foo2"            },
		{ hl="foo[1,1,2,1]",  delete="foo3",   n=0, result="foo[1,1-2,1]"    },
	},

	subtract = {
		{ hl ="foo[1-10]",  del = "foo[7,10]",  result = "foo[1-6,8-9]" },
		{ hl="foo[1,2,1]",  del = "foo1",       result = "foo2"         },
	},

	uniq = {
		["foo[1,2,1,2,1,1]"] = "foo[1-2]",
	},

	map = {
		{ hl="foo1,bar",   fn = 's:match("[^%d]$") and s', result = "bar" },
		-- Return only hosts divisible by 10
		{ hl="foo[1-100]", fn = '(s:match("[%d]+$")%10 == 0) and s',
			               result = "foo[10,20,30,40,50,60,70,80,90,100]" },
	},

	xor = {
		{ hl = "foo[1-100]", arg = "foo[2-101]", result = "foo[1,101]" },
	},

	intersect = {
		{ hl = "foo[1-100]", arg = "foo[2-101]", result = "foo[2-100]" },
		{ hl = "[0-5]",      arg = "4",          result = "4" },
	},

	union = {
		{ hl= { "16", "25" },	result="[16,25]" },
	},

	next = {
		"foo[1-50]", "", "foo[1,1,1]",
	},

	pop = {
		{ hl="foo[1-10]", pop=3,  result="foo[1-7]" },
		{ hl="foo[1-10]", pop=0,  result="foo[1-10]" },
		{ hl="foo[1-10]", pop=-3, result="foo[4-10]" },
	},

	find = {
		{ hl="foo[1-10]",       host="foo3",        result=3   }, 
		{ hl="foo[1-10]",       host="foo11",       result=nil }, 
		{ hl="foo[1-10]-eth0",  host="foo3-eth0",   result=3   }, 
		{ hl="[1-10]",          host="3",           result=3   }, 
		{ hl="t0,t",            host="t",           result=2   }, 
		{ hl="t,t0",            host="t",           result=1   }, 
		{ hl="i[00-05]",        host="i00",         result=1   }, 
		{ hl="i[00-05]",        host="i03",         result=4   }, 
		{ hl="[00-05]i",        host="00",          result=nil }, 
		{ hl="f00[1-5]",        host="f001",        result=1   }, 
		{ hl="f1-c2",           host="f2",          result=nil }, 
		{ hl="cornp2",          host="corn",        result=nil },
		{ hl="cornp2",          host="corn2",       result=nil },
		{ hl="corn-p2",         host="corn2",       result=nil },
	},
}

function test_new_nil_args()
	luaunit.assertIsUserdata (hostlist.new())
	luaunit.assertIsUserdata (hostlist.new(nil))
	luaunit.assertEquals (0, hostlist.new():count())
	local hl = hostlist.new()
	hl:concat ("")
	luaunit.assertEquals (0, #hl)
end


function test_hostlist_next()
	for _,s in pairs(TestHostlist.next) do
		local h = hostlist.new (s)
		local count = 0
		luaunit.assertIsUserdata (h)
		for host in h:next() do
			luaunit.assertIsString (host)
			count = count + 1
			luaunit.assertEquals (h[count], host)
		end
		luaunit.assertEquals (#h, count)
	end
end

function test_uniq ()
	for s,r in pairs (TestHostlist.uniq) do
		local h = hostlist.new (s)
		luaunit.assertIsUserdata (h)
		luaunit.assertEquals (r, tostring (h:uniq()))
	end
end

function test_expand()
	for s,r in pairs (TestHostlist.expand) do
		local h = hostlist.new (s)
		luaunit.assertIsUserdata (h)
		luaunit.assertEquals (r, table.concat (h:expand(), ","))
	end
end

function test_to_string()
	for s,r in pairs (TestHostlist.to_string) do
		local h = hostlist.new (s)
		luaunit.assertIsUserdata (h)
		luaunit.assertEquals (r, tostring (h))
	end
end

function test_count()
	for s,cnt in pairs (TestHostlist.counts) do

		luaunit.assertEquals (cnt, hostlist.count(s))

		local h = hostlist.new (s)
		luaunit.assertIsUserdata (h)
		luaunit.assertEquals (cnt, #h)
		luaunit.assertEquals (cnt, h:count())
	end
end

function test_index()
	local hl = hostlist.new ("foo[1-10]")
	luaunit.assertIsNil (hl[0])
	for _,t in pairs (TestHostlist.indeces) do
		local h = hostlist.new (t.hl)
		luaunit.assertIsUserdata (h)
		luaunit.assertEquals (t.result, h[t.index])
	end
end

function test_map ()
	for _,t in pairs (TestHostlist.map) do
		local fn, msg = loadstring ("return function(s) return "..t.fn.." end")
		luaunit.assertIsFunction (fn, msg)
		local result = hostlist.map (t.hl, fn())
		luaunit.assertIsUserdata (result)
		luaunit.assertEquals (t.result, tostring (result))
	end
end

function test_delete()
	for _,t in pairs (TestHostlist.delete) do
		local hl = hostlist.new (t.hl)
		luaunit.assertIsUserdata (hl)
		hl:delete (unpack(t.args))
		luaunit.assertEquals (t.result, tostring (hl))

		local s = hostlist.delete (t.hl, unpack (t.args))
		luaunit.assertEquals (t.result, tostring (s))
	end
end

function test_delete_n()
	for _,t in pairs (TestHostlist.delete_n) do
		local hl = hostlist.new (t.hl)
		luaunit.assertEquals (t.result, tostring (hl:delete_n(t.delete, t.n)))
	end
end

function test_pop()
	for _,t in pairs (TestHostlist.pop) do
		local hl = hostlist.new (t.hl)
		hl:pop(t.pop)
		luaunit.assertEquals (t.result, tostring (hl))
	end
end

function test_xor()
	for _,t in pairs (TestHostlist.xor) do
		local h = hostlist.xor (t.hl, t.arg)
		luaunit.assertIsUserdata (h)
		luaunit.assertEquals (t.result, tostring (h))
	end
end

function test_intersect()
	for _,t in pairs (TestHostlist.intersect) do
		local h = hostlist.intersect (t.hl, t.arg)
		luaunit.assertIsUserdata (h)
		luaunit.assertEquals (t.result, tostring (h))
	end
end

function test_union()
	for _,t in pairs (TestHostlist.union) do
		local h = hostlist.union (unpack(t.hl))
		luaunit.assertIsUserdata (h)
		luaunit.assertEquals (t.result, tostring (h))
	end
end

function test_subtract()
	for _,t in pairs (TestHostlist.subtract) do
		local h = hostlist.new (t.hl)
		luaunit.assertIsUserdata (h)
		local r = h - t.del
		luaunit.assertIsUserdata (r)
		luaunit.assertEquals (t.result, tostring (r))
	end
end

function test_find()
	for _,t in pairs (TestHostlist.find) do
		luaunit.assertEquals (t.result, hostlist.find (t.hl, t.host))
		local h = hostlist.new (t.hl)
		luaunit.assertIsUserdata (h)
		luaunit.assertEquals (t.result, h:find(t.host))
	end
end


os.exit (luaunit.LuaUnit.run())
