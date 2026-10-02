"""#1376 public diagnostic qualification; missing attribution is never zero work."""
import copy
import unittest
from m4_baseline_report import summarize_checkpoint_timings, evaluate
from run_m4_baseline import parse_arguments

class CheckpointReportTests(unittest.TestCase):
    def test_diagnostic_mode_is_explicit_and_requires_target_supported_load(self):
        image=['--server-image','sha256:'+'a'*64]
        self.assertFalse(parse_arguments(image).checkpoint_attribution)
        args=parse_arguments(image+['--supported-load','--crossing-span','10','--checkpoint-attribution'])
        self.assertTrue(args.checkpoint_attribution)
        self.assertEqual(args.worker_count,0)
        for flags in (['--checkpoint-attribution'], ['--supported-load','--checkpoint-attribution']):
            with self.assertRaises(SystemExit):
                parse_arguments(image+flags)
        result=evaluate({},True,checkpoint_attribution=True)
        self.assertFalse(result['checks']['checkpoint_child_evidence_qualified'])
        self.assertIn('checkpoint_child_evidence_qualified',result['failed_checks'])
        self.assertNotIn('checkpoint_child_evidence_qualified',evaluate({},True)['checks'])

    def test_truncated_window_cannot_qualify(self):
        samples=[{'tick':i+100,'physics_steps':1,'checkpoint_calls':1,'duration_usec':1000,'canon_read':{'calls':1,'duration_usec':600},'journey_save':{'calls':1,'duration_usec':300}} for i in range(1000)]
        baseline=[{'tick':x['tick'],'physics_steps':1,'stage_timings':{'journey_checkpoint':{'calls':1,'duration_usec':1100}}} for x in samples]
        record={'bindings':dict.fromkeys(('server_canon','server_journey','coordinator','registry','canon_store_original','journey_store_original'),True),'samples':samples[:1]}
        self.assertFalse(summarize_checkpoint_timings(record,baseline)['qualified'])

    def test_child_observations_require_real_bindings_and_preserve_residual_scope(self):
        record={'bindings':dict.fromkeys(('server_canon','server_journey','coordinator','registry','canon_store_original','journey_store_original'),True),
                'samples':[{'tick':100,'physics_steps':1,'checkpoint_calls':1,'duration_usec':1000,'canon_read':{'calls':1,'duration_usec':600},'journey_save':{'calls':1,'duration_usec':300}}]}
        baseline=[{'tick':100,'physics_steps':1,'stage_timings':{'journey_checkpoint':{'calls':1,'duration_usec':1100}}}]
        result=summarize_checkpoint_timings(record,baseline)
        self.assertTrue(result['qualified'])
        self.assertEqual(result['samples'][0]['inclusive_residual_usec'],100)
        self.assertNotIn('hash_duration_usec',result)
        for key in record['bindings']:
            broken=copy.deepcopy(record);broken['bindings'][key]=False
            self.assertFalse(summarize_checkpoint_timings(broken,baseline)['qualified'],key)
        for key in ('canon_read','journey_save'):
            broken=copy.deepcopy(record);del broken['samples'][0][key]
            self.assertFalse(summarize_checkpoint_timings(broken,baseline)['qualified'],key)
        broken=copy.deepcopy(record);broken['samples'][0]['canon_read']['duration_usec']=1100
        self.assertFalse(summarize_checkpoint_timings(broken,baseline)['qualified'])
        self.assertFalse(summarize_checkpoint_timings({})['qualified'])
        for field,value in (('tick',101),('physics_steps',2),('checkpoint_calls',0)):
            broken=copy.deepcopy(record);broken['samples'][0][field]=value
            self.assertFalse(summarize_checkpoint_timings(broken,baseline)['qualified'])
        duplicate=copy.deepcopy(record);duplicate['samples']*=2
        self.assertFalse(summarize_checkpoint_timings(duplicate,baseline*2)['qualified'])
        self.assertFalse(summarize_checkpoint_timings(record)['qualified'])

if __name__=='__main__':
    unittest.main(verbosity=2)
