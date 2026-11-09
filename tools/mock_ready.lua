-- Loaded before the addons for tests that drive Synastria's ready call: records the global the
-- module asks the server to call, for the test to call when it chooses.
SAFE_INVOKED = {}
function SynastriaSafeInvoke(name) SAFE_INVOKED[#SAFE_INVOKED + 1] = name end
