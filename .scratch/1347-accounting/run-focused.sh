#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
run="$1"
case "$run" in *[!a-zA-Z0-9_-]*|'') exit 2;; esac
result="$PWD/build/validation/1347-accounting/$run"
test ! -e "$result"
mkdir -p "$result/xdg"
export XDG_DATA_HOME="$result/xdg"
cleanup() {
  local cleanup_exit=0
  rm -rf -- "$XDG_DATA_HOME" || cleanup_exit=$?
  python3 - "$result" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]);f=p/'result.json'
if f.exists():
 r=json.loads(f.read_text());r['owned_xdg_removed']=not (p/'xdg').exists();r['status']=r['status'] if r['owned_xdg_removed'] else 'failed';f.write_text(json.dumps(r,indent=2)+'\n')
PY
  return "$cleanup_exit"
}
trap cleanup EXIT
set +e
timeout --kill-after=15s 900s godot --headless --import >"$result/import.log" 2>&1
import_exit=$?
timeout --kill-after=15s 180s godot --headless -s addons/gut/gut_cmdln.gd -gconfig= -gtest=res://tests/integration/test_canon_write_accounting.gd -gjunit_xml_file="$result/gut.xml" -gdisable_colors -gexit >"$result/gut.log" 2>&1
exit_code=$?
set -e
python3 - "$result" "$import_exit" "$exit_code" <<'PY'
import json,sys,subprocess,hashlib,xml.etree.ElementTree as ET
from pathlib import Path
p=Path(sys.argv[1]);actual=int(sys.argv[3]);root=None
try:
 root=ET.parse(p/'gut.xml')
except (ET.ParseError,OSError):
 pass
suites=list(root.iter('testsuite')) if root else []
selected=[s for s in suites if s.attrib.get('name')=='tests/integration/test_canon_write_accounting.gd']
status='passed' if actual==0 and int(sys.argv[2])==0 and len(selected)==1 else 'failed'
r={'command':'godot --headless -s addons/gut/gut_cmdln.gd -gconfig= -gtest=res://tests/integration/test_canon_write_accounting.gd -gdisable_colors -gexit','host':'192.168.1.254','engine':subprocess.check_output(['godot','--version'],text=True).strip(),'revision':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'import_exit':int(sys.argv[2]),'exit_code':actual,'selected_scripts_ran':len(selected),'status':status,'owned_xdg_removed':'NOT_OBSERVED','junit_suites':[s.attrib for s in suites]}
r['source_sha256']={name:hashlib.sha256(Path(name).read_bytes()).hexdigest() for name in ['server/sqlite_store.gd','server/sqlite_statement_observer.gd','tests/integration/test_canon_write_accounting.gd','.scratch/1347-accounting/run-focused.sh','addons/godot-sqlite/gdsqlite.gdextension'] if Path(name).is_file()}
r['native_sqlite_sha256']={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in Path('addons/godot-sqlite/bin').glob('*.so')}
(p/'result.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r))
if status!='passed':sys.exit(1)
PY
