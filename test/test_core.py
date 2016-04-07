import unittest
from hypothesis import given
from hypothesis.strategies import text
from cg3 import Applicator

class TestApplicator(unittest.TestCase):

    def setUp(self):
        self.applicator = Applicator('test/bm_morf-prestat-unicode.cg')


    @given(text())
    def test_create_tag(self, name):
        if not name or '\x00' in name:
            with self.assertRaises(ValueError):
                self.applicator.create_tag(name)
        else:
            tag = self.applicator.create_tag(name)
            self.assertEqual(str(tag), name)

    def test_parsing(self):
        with open('test/test.cg') as f:
            document = self.applicator.parse(f)
        self.assertEqual(str(document[1][0][1]), '"Karl"')

    def test_rules(self):
        with open('test/test.cg') as f:
            document = self.applicator.parse(f)
        self.assertEqual(len(document[6]), 4)
        self.applicator.run_rules(document)
        self.assertEqual(len(document[6]), 1)


if __name__ == '__main__':
    unittest.main()
