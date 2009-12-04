#!/usr/bin/lua 

--[[#########################################################################
#
#  glob-hosts.lua, a glob-hosts implemetation (slightly modified) in lua.
#  
#  A proof-of-concept production
#
--##########################################################################]]

local hostlist = require ("hostlist")
local prog     = string.match (arg[0], "([^/]+)$")

local usage    =
[[
Usage: %s [OPTION]... [HOSTLIST]...

  -h, --help                   Display this message.
  -c, --count                  Print the number of hosts
  -s, --size=N                 Output at most N hosts
  -e, --expand                 Expand host list instead of collapsing
  -n, --nth=N                  Output the host at index N (-N to index from end)
  -d, --delimiters=S           Set output delimiter (default = ",")
  -u, --union                  Union of all HOSTLIST arguments
  -m, --minus                  Subtract all HOSTLIST args from first HOSTLIST
  -i, --intersection           Intersection of two HOSTLIST args
  -x, --exclude                Exclude all HOSTLIST args from first HOSTLIST
  -X, --xor                    Symmetric difference (XOR) of all HOSTLIST args

 An arbitrary number of HOSTLIST arguments are supported for all
  operations except intersection and xor, where exactly 2 args are expected.
  The default operation is -u, --union.

]]
	
--[[#########################################################################
#
#  Functions:
#
--##########################################################################]]

function printf (...)
	io.write (string.format (...))
end

function log_msg (...)
	local fmt = string.format
	local msg = fmt (...)
	io.stderr:write (fmt ("%s: %s", prog, msg))
end

function log_fatal (...)
	log_msg ("Fatal: ".. ...)
	os.exit (1)
end

function log_err (...)
	log_msg ("Error: ".. ...)
end

function log_verbose (...)
	if (verbose) then log_msg (...) end
end


function display_usage ()
	printf (usage, prog)
	os.exit (0)
end

function parse_cmdline (arg)
	local alt_getopt = (require "alt_getopt")
	local getopt     = alt_getopt.get_opts

	local optstring = "hcen:d:s:umixX"
	local opt_table = {
		help                 = "h",
		count                = "c",
		size                 = "s",
		expand               = "e",
		nth                  = "n",
		delimiters           = "d",
		hosts                = "h",
		union                = "u",
		minus                = "m",
		intersection         = "i",
		exclude              = "x",
		xor                  = "X",
	}

    return getopt (arg, optstring, opt_table)
end

function convert_string_to_escape (s)
	local t = { t='\t', n='\n', f='\f', v='\v', t='\t' }
	local c1 = s:sub(1,1)
	local c2 = s:sub(2,2)

	if c1 == '\\' and t[c2] then
		return t[c2]
	end
	return s
end

function check_opts (opts, input)
	
	local n = 0
	for _,opt in ipairs({u, m, i, x}) do
		if opts[opt] ~= nil then n = n + 1 end
	end

	if (n > 1) then
		log_fatal ("Only one of -[umix] may be used")
	end

	--  Convert delimiter to escape sequence if necessary
	--   For some reason args passed to lua like '\n' come in
	--   as a string with characters "\" and "\n"
	--
	opts.d = opts.d and convert_string_to_escape (opts.d) or ","

	--
	--  Check number of args to xor or intersect
	--
	if (opts.i or opts.X) and (#input ~= 2) then
		log_fatal ("intersect/xor require exactly two hostlist args\n")
	end
end

function hostlist_from_stdin ()
	local hl = {}
	for line in io.lines() do
		for word in line:gmatch ('%S+') do table.insert (hl, word) end
	end
	return hl
end

function hostlist_from_args (args, optind)
	local hl = {}
	for i = optind, #args do
		table.insert (hl, args[i])
	end
	return hl
end

---
---  Output the resulting hostlist in [hl] according to options
---
function hostlist_output (opts, hl)
	local n = #hl
	local size = tonumber (opts.s) or n
	local delim = opts.d

	if size < n then
		hl:pop(n - size)
	end

	if opts.n then
		print (hl[opts.n])
	elseif opts.e then
		print (table.concat(hl:map(), delim))
	else
		print (hl)
	end
end

--[[#########################################################################
#
#  Main:
#
--##########################################################################]]

--
-- Process cmdline args
--
local hl          -- Result hostlist
local input = {}  -- Table of input values

local opts, optind = parse_cmdline (arg)

if opts.h then display_usage () end

-- Get all hostlist arguments into a table (from either cmdline or stdin)
if optind <= #arg then
	input = hostlist_from_args (arg, optind)
else
	input = hostlist_from_stdin ()
end

-- Sanity check options:
check_opts (opts, input)

if opts.u then
	hl = hostlist.union (unpack (input))
elseif opts.m or opts.x then
	hl = hostlist.delete (unpack (input))
elseif opts.i then
	hl = hostlist.intersect (unpack (input))
elseif opts.X then
	hl = hostlist.xor (unpack (input))
else
	hl = hostlist.union (unpack (input))
	hl:uniq()
end

-- `minus' and `exclude' are the same afaict, so we make them
--   differ by having the --minus option return a uniq'd list:
if opts.m then hl:uniq() end

if (hl) then hostlist_output (opts, hl) end

os.exit (0)
