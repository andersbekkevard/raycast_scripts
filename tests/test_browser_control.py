import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('browser_control', Path(__file__).resolve().parents[1] / 'lib/browser_control.py')
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)


def window(*urls, selected=0, wid=1):
    return {'id': wid, 'tabs': [dict(window=wid, index=i+1, url=url, active=i==selected) for i,url in enumerate(urls)]}


class SelectionTests(unittest.TestCase):
    def setUp(self):
        self.cfg = dict(default_browser='Aside', browsers=['Aside', 'Comet', 'Safari'],
                        reuse_matching_tabs=True, prefer_focused_browser=True,
                        reuse_single_open_browser=True, cycle_matching_tabs=True)

    def test_browser_rules(self):
        cases = [
            ({}, 'Finder', (), 'Aside'),
            ({'Comet': []}, 'Finder', (), 'Aside'),
            ({'Comet': [window('x')]}, 'Finder', (), 'Comet'),
            ({'Aside': [window('x')], 'Comet': [window('y')]}, 'Finder', (), 'Aside'),
            ({'Aside': [window('x')], 'Comet': [window('y')]}, 'Comet', (), 'Comet'),
            ({'Aside': [window('x')], 'Comet': [window('target')]}, 'Aside', ['target'], 'Comet'),
            ({'Aside': [window('target')], 'Comet': [window('target')]}, 'Finder', ['target'], 'Aside'),
            ({'Aside': [window('target')], 'Comet': [window('target')]}, 'Comet', ['target'], 'Comet'),
        ]
        for windows, front, patterns, expected in cases:
            with self.subTest(front=front, expected=expected, windows=windows):
                self.assertEqual(b.select_browser(self.cfg, windows, front, patterns), expected)

    def test_background_focus_does_not_cycle(self):
        windows = {'Comet': [window('target/1', 'target/2')]}
        with patch.object(b, 'bridge') as bridge:
            b.focus({'url_patterns':['target']}, self.cfg, {'front':'Finder'}, windows)
            self.assertEqual(bridge.call_args.args[2]['url'], 'target/1')
            b.focus({'url_patterns':['target']}, self.cfg, {'front':'Comet'}, windows)
            self.assertEqual(bridge.call_args.args[2]['url'], 'target/2')

    def test_cycle_wraps_within_browser(self):
        windows = [window('target/1','target/2', selected=1)]
        self.assertEqual(b.select_tab(windows,['target'], True)['url'], 'target/1')
        self.assertEqual(b.select_tab(windows,['target'], False)['url'], 'target/2')

    def test_configuration_can_disable_context_routing(self):
        self.cfg.update(reuse_matching_tabs=False, prefer_focused_browser=False, reuse_single_open_browser=False)
        self.assertEqual(b.select_browser(self.cfg, {'Comet':[window('target')]}, 'Comet',['target']), 'Aside')

    def test_closed_browsers_are_not_queried(self):
        with patch.object(b,'bridge',return_value=[]) as bridge:
            b.inventory(self.cfg, {'running':['Comet']})
            bridge.assert_called_once_with('Comet','snapshot')

    def test_active_requires_window(self):
        with self.assertRaisesRegex(RuntimeError, 'No unambiguous'):
            b.active(self.cfg, {'front':'Finder'}, {'Comet':[]})


if __name__ == '__main__':
    unittest.main()
