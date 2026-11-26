import json, re, sys
from pathlib import Path
p = Path(sys.argv[1] if len(sys.argv) > 1 else r"D:\Administrator\Documents\ai\k60p_build\work\actions.html")
c = p.read_text(encoding="utf-8", errors="replace")
m = re.search(r'"workflowRuns":(\[.*?\])\s*,\s*"', c, re.S) or re.search(r'"workflowRuns":(\[.*?\])', c, re.S)
if not m:
    print("workflowRuns not found"); sys.exit(1)
runs = json.loads(m.group(1))
for r in runs[:8]:
    st = r.get("state", {})
    print(r.get("name"), r.get("runNumber"), r.get("id"), st.get("status"), st.get("conclusion", ""), r.get("createdAt", {}).get("timestamp"), r.get("timing", {}).get("text", ""))
