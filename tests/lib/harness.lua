-- Shared by every *.test.lua: check(cond, msg) records a result; done()
-- hands the totals back to run.js. Only failures print unless VERBOSE.

local passed, failures = 0, 0

function check(cond, msg)
	if cond then
		passed = passed + 1
		if VERBOSE then print("    ok   " .. msg) end
	else
		failures = failures + 1
		print("    FAIL " .. msg)
	end
end

-- Diagnostic output, shown only with `node run.js -v`.
function vprint(...)
	if VERBOSE then print(...) end
end

function done()
	TEST_PASSED, TEST_FAILURES = passed, failures
end
