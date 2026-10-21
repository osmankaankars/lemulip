"""Presentation requirements kept independent of conversion behavior."""
from pathlib import Path
from html.parser import HTMLParser
import unittest
ROOT=Path(__file__).resolve().parent.parent
class Nodes(HTMLParser):
    def __init__(self):super().__init__();self.nodes=[]
    def handle_starttag(self,tag,attrs):self.nodes.append((tag,dict(attrs)))
class PresentationTests(unittest.TestCase):
    def setUp(self):
        self.html=(ROOT/'site/index.html').read_text()
        self.js=(ROOT/'site/product.js').read_text()
        self.nodes=Nodes();self.nodes.feed(self.html)
    def test_all_nine_samples_are_files_not_a_dropdown(self):
        buttons=[a['data-sample'] for t,a in self.nodes.nodes if t=='button' and 'data-sample' in a]
        self.assertEqual(9,len(buttons));self.assertEqual(9,len(set(buttons)))
        self.assertNotIn('id="sample-type"',self.html)
    def test_theme_is_in_the_header(self):
        header=self.html.split('<header',1)[1].split('</header>',1)[0]
        self.assertIn('id="appearance"',header)
        self.assertEqual(1,self.html.count('id="appearance"'))
    def test_workspace_is_part_of_the_existing_demo(self):
        self.assertIn('id="origin-workspace"',self.html)
        self.assertIn('class="workspace-window"',self.html)
        self.assertIn('id="workspace-status"',self.html)
    def test_copy_is_reduced_without_losing_disclosure(self):
        for term in ('Interactive example','No Lemulip window needed','Your desktop.','\u2014','\u2013'):
            self.assertNotIn(term,self.html);self.assertNotIn(term,self.js)
        self.assertIn('Browser Simulation',self.html)
        self.assertIn('File Tools.',self.html);self.assertIn('Right Where',self.html)
        self.assertIn('Different Files.',self.html);self.assertIn('Start With A Drag.',self.html)
    def test_format_notes_use_separate_paragraphs(self):
        self.assertIn('class="engine-note"',self.js)
        self.assertIn('ImageMagick',self.js)
    def test_compact_controls_and_colored_shortcuts(self):
        self.assertIn('class="demo-controls"',self.html)
        for name in ('shortcut-convert','shortcut-tools','shortcut-actions'):
            self.assertIn(name,self.html)
if __name__=='__main__':unittest.main()
