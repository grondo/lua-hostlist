
require "lunit"
require "hostlist"

module ("TestHostlist", lunit.testcase, package.seeall) 

TestHostlist = {

	to_string = {
		["1,2,3,5,6"] =      "[1-3,5-6]"
	},

	expand = {
		["foo[1-5]"] =       "foo1,foo2,foo3,foo4,foo5",
		["foo[0-4]-eth2"] =  "foo0-eth2,foo1-eth2,foo2-eth2,foo3-eth2,foo4-eth2",
		["foo1,foo1,foo1"] = "foo1,foo1,foo1",
	},

	counts = {
		["foo[1,1,1]"] = 3
	},

	indeces = {
		{ hl="foo[1-100]",  index=50,        result="foo50"            },
	},

	delete = {
		{ hl="foo[1-5]",    delete="foo3",   result="foo[1-2,4-5]"     },
		{ hl="foo[1,2,1]",  delete="foo1",   result="foo2"             },
	},

	["delete_n"] = {
		{ hl="foo[1,2,1]",  delete="foo1",   n=1, result="foo[2,1]"    },
	},

	subtract = {
		{ hl ="foo[1-10]",  del = "foo[7,10]",  result = "foo[1-6,8-9]" },
		{ hl="foo[1,2,1]",  del = "foo1",       result = "foo2"         },
	}
}

function test_expand()
	for s,r in pairs (TestHostlist.expand) do
		local h = hostlist.new (s)
		assert_userdata (h)
		assert_equal (r, table.concat (h:map(), ","))
	end
end

function test_to_string()
	for s,r in pairs (TestHostlist.to_string) do
		local h = hostlist.new (s)
		assert_userdata (h)
		assert_equal (r, tostring (h))
	end
end

function test_count()
	for s,cnt in pairs (TestHostlist.counts) do
		local h = hostlist.new (s)
		assert_userdata (h)
		assert_equal (cnt, #h)
	end
end

function test_index()
	for _,t in pairs (TestHostlist.indeces) do
		local h = hostlist.new (t.hl)
		assert_userdata (h)
		assert_equal (t.result, h[t.index])
	end
end

function test_delete()
	for _,t in pairs (TestHostlist.delete) do
		local hl = hostlist.new (t.hl)
		assert_userdata (hl)
		hl:delete (t.delete)
		assert_equal (t.result, tostring (hl))
	end
end

function test_delete_n()
	for _,t in pairs (TestHostlist.delete_n) do
		local hl = hostlist.new (t.hl)
		assert_equal (t.result, tostring (hl:delete_n(t.delete, t.n)))
	end
end

function test_subtract()
	for _,t in pairs (TestHostlist.subtract) do
		local h = hostlist.new (t.hl)
		assert_userdata (h)
		local r = h - t.del
		assert_userdata (r)
		assert_equal (t.result, tostring (r))
	end
end
