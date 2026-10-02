"""#1376 public diagnostic qualification; missing attribution is never zero work."""
import copy
import unittest
from m4_baseline_report import summarize_checkpoint_timings

class CheckpointReportTests(unittest.TestCase):
    def test_child_observations_require_real_bindings_and_preserve_residual_scope(self):
        record={'bindings':dict.fromkeys(('server_canon','server_journey','coordinator','registry','canon_store_original','journey_store_original'),True),
                'samples':[{'checkpoint_calls':1,'duration_usec':1000,'canon_read':{'calls':1,'duration_usec':600},'journey_save':{'calls':1,'duration_usec':300}}]}
        result=summarize_checkpoint_timings(record)
        self.assertTrue(result['qualified'])
        self.assertEqual(result['samples'][0]['inclusive_residual_usec'],100)
        self.assertNotIn('hash_duration_usec',result)
        for key in record['bindings']:
            broken=copy.deepcopy(record);broken['bindings'][key]=False
            self.assertFalse(summarize_checkpoint_timings(broken)['qualified'],key)
        for key in ('canon_read','journey_save'):
            broken=copy.deepcopy(record);del broken['samples'][0][key]
            self.assertFalse(summarize_checkpoint_timings(broken)['qualified'],key)
        broken=copy.deepcopy(record);broken['samples'][0]['canon_read']['duration_usec']=1100
        self.assertFalse(summarize_checkpoint_timings(broken)['qualified'])
        self.assertFalse(summarize_checkpoint_timings({})['qualified'])

if __name__=='__main__':
    unittest.main(verbosity=2)
