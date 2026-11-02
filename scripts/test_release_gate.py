import unittest
from verify_release import passed_nodes, validate_summary

class ReleaseGateTests(unittest.TestCase):
    def test_only_complete_success_is_accepted(self):
        validate_summary(dict(result="Passed", totalTestCount=5, passedTests=5,
                              failedTests=0, skippedTests=0, expectedFailures=0))

    def test_failures_skips_empty_and_partial_runs_cannot_release(self):
        valid = dict(result="Passed", totalTestCount=5, passedTests=5,
                     failedTests=0, skippedTests=0, expectedFailures=0)
        for patch in ({"result":"Failed"}, {"failedTests":1}, {"skippedTests":1},
                      {"expectedFailures":1}, {"totalTestCount":0}, {"passedTests":4},
                      {"failedTests":None}):
            with self.subTest(patch=patch), self.assertRaises(ValueError):
                validate_summary(valid | patch)

    def test_only_actual_passed_test_cases_count(self):
        tree = {"testNodes":[{"nodeType":"Test Suite", "nodeIdentifier":"Suite", "result":"Passed", "children":[
            {"nodeType":"Test Case", "nodeIdentifier":"Suite/pass()", "result":"Passed"},
            {"nodeType":"Test Case", "nodeIdentifier":"Suite/skip()", "result":"Skipped"},
            {"nodeType":"Test Case", "nodeIdentifier":"Suite/fail()", "result":"Failed"}]}]}
        self.assertEqual(passed_nodes(tree), {"Suite/pass()"})


class FullReleaseGateTests(unittest.TestCase):
    def test_complete_evidence_and_adversarial_rejections(self):
        import copy, hashlib, json, pathlib, plistlib, tempfile, zipfile
        from unittest.mock import patch
        import verify_release as gate
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            (root/'FueliUITests').mkdir(); (root/'FueliTests').mkdir()
            (root/'project.yml').write_text('MARKETING_VERSION: "1.0.14"')
            (root/'FueliUITests/AppJourneyTests.swift').write_text('func testJourney() {}')
            (root/'FueliTests/ReleaseLiveTests.swift').write_text('@Test func requiredProbe() {}')
            suites = ['NutritionSafetyTests','PersistenceActionTests','RigorousDomainTests','AIWireContractTests','MealDatabaseChoiceTests']
            ids = ['AppJourneyTests/testJourney()', 'ReleaseLiveTests/requiredProbe()'] + [s+'/probe()' for s in suites]
            summary = dict(result='Passed', totalTestCount=len(ids), passedTests=len(ids), failedTests=0, skippedTests=0, expectedFailures=0)
            tree = {'testNodes':[dict(nodeType='Test Case', result='Passed', nodeIdentifier=i) for i in ids]}
            ipa = root/'Fueli.ipa'; evidence = root/'evidence.json'
            info = {'CFBundleIdentifier':'com.welford.fueli','CFBundleShortVersionString':'1.0.14','USDA_API_KEY':''}
            def package(values):
                with zipfile.ZipFile(ipa,'w') as z: z.writestr('Payload/Fueli.app/Info.plist',plistlib.dumps(values))
            package(info)
            valid = {'version':1,'sourceCommit':'fixture-commit','sourceFingerprint':'fixture-source',
                     'ipaSHA256':hashlib.sha256(ipa.read_bytes()).hexdigest(),'resultBundles':['fixture.xcresult'],
                     'physicalChecks':{key:'user-confirmed' for key in gate.DEVICE_CHECKS}}
            state = {'dirty':False,'summary':summary,'tree':tree}
            def output(args, **kwargs):
                if args[:3] == ['git','rev-parse','HEAD']: return 'fixture-commit\n'
                if args[:3] == ['git','status','--porcelain']: return ' M untested.swift' if state['dirty'] else ''
                if args[4] == 'summary': return json.dumps(state['summary']).encode()
                if args[4] == 'tests': return json.dumps(state['tree']).encode()
                self.fail('Unexpected external operation')
            with patch.object(gate,'ROOT',root), patch.object(gate,'source_fingerprint',return_value='fixture-source'), patch.object(gate.subprocess,'check_output',side_effect=output):
                evidence.write_text(json.dumps(valid))
                self.assertEqual(gate.verify(evidence,ipa),len(ids))
                for change in ({'version':999},{'sourceCommit':'old'},{'sourceFingerprint':'changed'},
                               {'ipaSHA256':'wrong'},{'physicalChecks':{}},{'resultBundles':[]}):
                    with self.subTest(change=change), self.assertRaises(ValueError):
                        evidence.write_text(json.dumps(valid | change)); gate.verify(evidence,ipa)
                evidence.write_text(json.dumps(valid)); state['dirty']=True
                with self.assertRaises(ValueError): gate.verify(evidence,ipa)
                state['dirty']=False
                for field in ['failedTests','skippedTests','expectedFailures']:
                    state['summary']=summary | {field:1}
                    with self.subTest(field=field), self.assertRaises(ValueError): gate.verify(evidence,ipa)
                state['summary']=summary
                state['tree']={'testNodes':tree['testNodes'][1:]}
                with self.assertRaises(ValueError): gate.verify(evidence,ipa)
                state['tree']=tree
                for change in ({'CFBundleIdentifier':'wrong.bundle'}, {'CFBundleShortVersionString':'1.0'}, {'USDA_API_KEY':'fixture-key'}):
                    package(info | change)
                    altered=copy.deepcopy(valid); altered['ipaSHA256']=hashlib.sha256(ipa.read_bytes()).hexdigest()
                    evidence.write_text(json.dumps(altered))
                    with self.subTest(info=change), self.assertRaises(ValueError): gate.verify(evidence,ipa)

if __name__ == '__main__': unittest.main()
