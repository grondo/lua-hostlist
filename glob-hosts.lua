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
  -q, --quiet                  Quiet output (exit non-zero if empty hostlist).
  -d, --delimiters=S           Set output delimiter (default = ",")
  -c, --count                  Print the number of hosts
  -s, --size=N                 Output at most N hosts (-N for last N hosts)
  -e, --expand                 Expand host list instead of collapsing
  -n, --nth=N                  Output the host at index N (-N to index from end)
  -u, --union                  Union of all HOSTLIST arguments
  -m, --minus                  Subtract all HOSTLIST args from first HOSTLIST
  -i, --intersection           Intersection of all HOSTLIST args
  -x, --exclude                Exclude all HOSTLIST args from first HOSTLIST
  -X, --xor                    Symmetric difference of all HOSTLIST args
  -R, --remove=N               Remove only N occurrences of args from HOSTLIST
  -f, --filter=CODE            Map Lua CODE over all hosts in result HOSTLIST
  -F, --find=HOST              Output position of HOST in result HOSTLIST
                                (exits non-zero if host not found)

 An arbitrary number of HOSTLIST arguments are supported for all
  operations.  The default operation is to concatenate all HOSTLIST args.

]]
	
-- Only one of the following options may be specified:
local exclusive_options = { "u", "m", "i", "x", "X", "R" }

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
	local args = {...}
	args[1] = "Fatal: " .. args[1]
	log_msg (unpack(args))
	os.exit (1)
end

function log_err (...)
	local args = {...}
	args[1] = "Error: " .. args[1]
	log_msg (unpack(args))
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

	local optstring = "hqcen:d:R:f:F:s:umixX"
	local opt_table = {
		help                 = "h",
		quiet                = "q",
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
		remove               = "D",
		filter               = "f",
		find                 = "F",
	}

    return getopt (arg, optstring, opt_table)
end

--
--  Return the 
--
function convert_string_to_escape (s)
	local t = { t='\t', n='\n', f='\f', v='\v', t='\t', r='\r',}
	return s:sub(1,1) == '\\' and t[s:sub(2,2)] or s
end

function check_opts (opts)
	
	--
	--  Check that no more than one exlusive option was passed:
	--
	local n = 0
	for _,opt in pairs(exclusive_options) do
		if opts[opt] ~= nil then n = n + 1 end
	end

	if (n > 1) then
		log_fatal ("Only one of -[%s] may be used\n",
				table.concat(exclusive_options))
	end

	--  Convert delimiter to escape sequence if necessary
	--   For some reason args passed to lua like '\n' come in
	--   as a string with characters "\" and "\n"
	--
	opts.d = opts.d and convert_string_to_escape (opts.d) or ","

	--
	-- Compile filter function if one was supplied
	-- 
	if (opts.f ~= nil) then 
		local fn, msg = loadstring ("return function (s) return "..opts.f.." end")
		if (fn == nil) then
			log_fatal ("Failed to compile filter option: %s\n", msg)
		end
		opts.f = fn
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
	local sign = size / math.abs (size)
	local delim = opts.d

	-- Pop or shift N hosts if requested:
	hl:pop(sign * (n - math.abs(size)))

	if opts.n then
		local host = hl[opts.n]
		if (opts.q or host == nil) then os.exit (host and 0 or 1) end
		print (host)
	elseif opts.q then
		os.exit (#hl and 0 or 1)
	elseif opts.c then
		print (#hl)
	elseif opts.e then
		print (table.concat(hl:expand(), delim))
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

-- Sanity check options:
check_opts (opts, input)

-- Get all hostlist arguments into a table (from either cmdline or stdin)
if optind <= #arg then
	input = hostlist_from_args (arg, optind)
else
	input = hostlist_from_stdin ()
end

-- Handle options u, i, X, x, m, D
if opts.u then
	-- Union
	hl = hostlist.union (unpack (input))
elseif opts.i then
	-- Intersection
	hl = hostlist.intersect (unpack (input))
elseif opts.X then
	-- XOR or symmetric set difference
	hl = hostlist.xor (unpack (input))
elseif opts.x then
	-- Delete all hosts
	hl = hostlist.delete (unpack (input))
elseif opts.m then
	--  Like delete, but treat hostlists as sets
	hl = hostlist.delete (unpack (input)):uniq()
elseif opts.R then
	--  Delete the first N hosts (opts.R) from each hostlist
	for _,v in pairs(input) do
		hl = hl and hl:delete_n (v, opts.R) or hostlist.new (v)
	end
else
	-- Default: Append all hosts
	hl = hostlist.concat (unpack (input))
end

-- Filter result if requested
if opts.f then hl = hl:map(opts.f()) end

-- Find host in result if requested
if opts.F then
	local n = hl:find (opts.F)
	if opts.q or n == nil then os.exit (n == nil and 1 or 0) end
	print (n)
	os.exit (0)
end

if (#hl > 0) then hostlist_output (opts, hl) else os.exit (1) end

os.exit (0)
