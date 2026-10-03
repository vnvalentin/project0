#!/usr/bin/env python3
"""Copied #1423 command controls. Python adapters only; no Godot or sockets."""
import argparse
import ast
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FOCUS = ROOT/'.scratch/1423/run-focused.py'


class FocusControls(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='project0-1423-copied-control.')
        self.root = Path(self.temporary.name)/'source'
        (self.root/'.scratch/1423').mkdir(parents=True)
        (self.root/'scripts').mkdir()
        (self.root/'tests/unit').mkdir(parents=True)
        (self.root/'addons/godot-sqlite').mkdir(parents=True)
        (self.root/'adapter').mkdir()
        self.wrapper = self.root/'.scratch/1423/run-focused.py'
        self.adapter = self.root/'adapter/godot'
        self.calls = Path(self.temporary.name)/'adapter-calls.jsonl'
        self.original_hash = hashlib.sha256(FOCUS.read_bytes()).hexdigest()
        self.environment = {'PATH':'/usr/bin:/bin','LANG':'C.UTF-8','HOME':self.temporary.name,
                            'GIT_CONFIG_NOSYSTEM':'1','GIT_CONFIG_GLOBAL':'/dev/null','GIT_TERMINAL_PROMPT':'0'}
        self.wrapper.write_bytes(FOCUS.read_bytes())
        shutil.copyfile(ROOT/'scripts/prepare_godot_project.py',self.root/'scripts/prepare_godot_project.py')
        (self.root/'project.godot').write_text('config_version=5\n\n[application]\nconfig/name="Project0"\n\n[editor_plugins]\nenabled=PackedStringArray("res://addons/gut/plugin.cfg")\n')
        (self.root/'addons/godot-sqlite/gdsqlite.gdextension').write_text('; synthetic registry declaration\n')
        (self.root/'tests/unit/test_lan_config.gd').write_text('extends GutTest\nfunc test_defaults_to_localhost_with_no_override() -> void:\n\tpass\n')
        (self.root/'.gitignore').write_text('build/\n.godot/\n__pycache__/\n')
        (self.root/'.scratch/1423/validation-plan.json').write_text('{}\n')
        (self.root/'scripts/check_validation_ownership.py').write_text('import json,sys\nfrom pathlib import Path\nPath(sys.argv[sys.argv.index("--output")+1]).write_text(json.dumps({"passed":True,"errors":[],"runtime_executed":False}))\n')

    def tearDown(self):
        self.temporary.cleanup()
        self.assertEqual(hashlib.sha256(FOCUS.read_bytes()).hexdigest(),self.original_hash)

    def git(self,*arguments):
        return subprocess.check_output(['/usr/bin/git','-c','core.fsmonitor=false','-c','core.hooksPath=/dev/null',*arguments],
            cwd=self.root,env=self.environment,stderr=subprocess.DEVNULL,timeout=10).decode().strip()

    def configure(self,exit_code=1,lifecycle_missing=False,lifecycle_drift=False,lock_missing=False,helper_missing=False,helper_drift=False):
        self.adapter.write_text('''#!/usr/bin/python3
import json,os,signal,sys
from pathlib import Path
calls=Path('''+repr(str(self.calls))+''')
with calls.open('a') as output: output.write(json.dumps({'version':'--version' in sys.argv,'import':'--import' in sys.argv})+'\\n')
if '--version' in sys.argv:
    print('4.3.stable.official.77dcf97d8');raise SystemExit(0)
if '--import' in sys.argv: raise SystemExit(0)
target=next(argument.split('=',1)[1] for argument in sys.argv if argument.startswith('-gjunit_xml_file='))
Path(target).write_text('<testsuites tests="1" failures="1"><testsuite name="tests/unit/test_lan_config.gd" tests="1" failures="1" skipped="0"><testcase name="test_defaults_to_localhost_with_no_override" classname="tests/unit/test_lan_config.gd" assertions="3" status="fail"><failure message="synthetic">fixed copied assertion failure</failure></testcase></testsuite></testsuites>')
code='''+repr(exit_code)+'''
if code<0: os.kill(os.getpid(),-code)
raise SystemExit(code)
''')
        self.adapter.chmod(0o755)
        tree=ast.parse(self.wrapper.read_text())
        adapter_root=str(self.adapter.parent)
        missing_path=Path(self.temporary.name)/'missing-lifecycle.py'
        drift_path=Path(self.temporary.name)/'drift-lifecycle.py'
        lock_path=Path(self.temporary.name)/('missing-lock-parent/shared.lock' if lock_missing else 'shared.lock')
        if lifecycle_drift:
            drift_path.write_text("raise AssertionError('unqualified lifecycle must not execute')\n")
        class Adjust(ast.NodeTransformer):
            def visit_Attribute(self,node):
                if isinstance(node.value,ast.Name) and node.value.id=='lifecycle' and node.attr=='LOCK':
                    return ast.copy_location(ast.parse('Path('+repr(str(lock_path))+')',mode='eval').body,node)
                return self.generic_visit(node)
            def visit_Assign(self,node):
                self.generic_visit(node)
                for target in node.targets:
                    if isinstance(target,ast.Name) and target.id=='LIFECYCLE' and (lifecycle_missing or lifecycle_drift):
                        node.value=ast.parse('Path('+repr(str(missing_path if lifecycle_missing else drift_path))+')',mode='eval').body
                return node
            def visit_Constant(self,node):
                if node.value=='/usr/local/bin:/usr/bin:/bin':
                    return ast.copy_location(ast.Constant(adapter_root+':/usr/bin:/bin'),node)
                return node
        tree=Adjust().visit(tree);ast.fix_missing_locations(tree)
        content=ast.unparse(tree)+'\n'
        self.wrapper.write_text(content)
        helper=self.root/'scripts/prepare_godot_project.py'
        if helper_missing: helper.unlink()
        if helper_drift: helper.write_text("raise AssertionError('unqualified helper must not execute')\n")
        self.git('init','-q');self.git('add','.')
        self.git('-c','user.name=Copied command fixture','-c','user.email=fixture@example.invalid','-c','commit.gpgsign=false','commit','-qm','Owned synthetic command source')
        self.revision=self.git('rev-parse','HEAD')

    def run_focus(self):
        result=subprocess.run(['/usr/bin/python3',str(self.wrapper),'--source-revision',self.revision,'--run-id','control','--mode','red'],
            cwd=self.root,env=self.environment,capture_output=True,text=True,timeout=140)
        path=self.root/'build/validation/1423/control/result.json'
        self.assertTrue(path.is_file(),'fixed structured failure result missing')
        return result,json.loads(path.read_bytes())

    def test_missing_lifecycle_records_failed_setup_without_adapter(self):
        self.configure(lifecycle_missing=True)
        result,record=self.run_focus()
        self.assertEqual(result.returncode,1)
        self.assertEqual(record['status'],'failed')
        self.assertFalse(self.calls.exists())
        self.assertNotIn('Traceback',result.stderr)

    def test_drifted_lifecycle_records_failed_setup_without_import_or_adapter(self):
        self.configure(lifecycle_drift=True)
        result,record=self.run_focus()
        self.assertEqual(result.returncode,1)
        self.assertEqual(record['status'],'failed')
        self.assertFalse(self.calls.exists())
        self.assertNotIn('unqualified lifecycle must not execute',result.stderr)

    def test_unavailable_lock_records_failed_setup_without_adapter(self):
        self.configure(lock_missing=True)
        result,record=self.run_focus()
        self.assertEqual(result.returncode,1)
        self.assertEqual(record['status'],'failed')
        self.assertFalse(self.calls.exists())
        self.assertNotIn('Traceback',result.stderr)

    def test_missing_or_drifted_helper_records_failure_before_adapter(self):
        for missing in (True,False):
            with self.subTest(missing=missing):
                # Each scenario uses its own normal test lifecycle.
                if not missing:
                    self.temporary.cleanup();self.setUp()
                self.configure(helper_missing=missing,helper_drift=not missing)
                result,record=self.run_focus()
                self.assertEqual(result.returncode,1)
                self.assertEqual(record['status'],'failed')
                self.assertFalse(self.calls.exists())
                self.assertNotIn('unqualified helper must not execute',result.stderr)

    def test_red_rejects_crash_with_complete_failure_xml(self):
        self.configure(exit_code=-6)
        result,record=self.run_focus()
        self.assertEqual(record['gut']['exit_code'],-6)
        self.assertTrue(record['junit']['expected_verdict'])
        self.assertEqual(result.returncode,1)
        self.assertEqual(record['status'],'failed')
        self.assertTrue(record['process_cleanup_verified'])
        self.assertTrue(record['temporary_cleanup_verified'])

    def test_red_accepts_only_assertion_exit_one_with_complete_xml(self):
        self.configure(exit_code=1)
        result,record=self.run_focus()
        self.assertEqual(result.returncode,0)
        self.assertEqual(record['status'],'passed')
        self.assertEqual(record['gut']['exit_code'],1)
        self.assertTrue(record['process_cleanup_verified'])
        self.assertTrue(record['temporary_cleanup_verified'])


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report',type=Path,required=True)
    args=parser.parse_args()
    suite=unittest.defaultTestLoader.loadTestsFromTestCase(FocusControls)
    result=unittest.TextTestRunner(verbosity=2).run(suite)
    args.report.parent.mkdir(parents=True,exist_ok=True)
    args.report.write_text(json.dumps({'passed':result.wasSuccessful(),'tests':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),'skipped':len(result.skipped),'native_godot_executed':False,'actual_source_preserved':True},indent=2)+'\n')
    raise SystemExit(not result.wasSuccessful())
