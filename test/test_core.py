from hypothesis import given
from hypothesis.strategies import (
    text, characters, none, recursive, composite, lists, just, tuples)
from unittest import TestCase
from cg3 import Reading, Cohort, Document, Applicator
from re import sub
from string import punctuation, ascii_letters

def tag():
    chars = ascii_letters + 'æøå'
    return text(alphabet=chars, min_size=1)

def punct_tag():
    return text(alphabet=punctuation, min_size=1, max_size=1)

def part_of_speech():
    return lists(tag(), min_size=1, max_size=5)

@composite
def reading(draw):
    lexeme = draw(tag() | punct_tag())
    lexeme = sub('^(['+punctuation+'])$', '$\\1', lexeme)
    lexeme = '"' + lexeme + '"'
    PoS = draw(part_of_speech())
    return Reading(lexeme, PoS)

@composite
def cohort(draw):
    readings = draw(lists(reading(), min_size=1, max_size=5))
    wordform = '"<' + draw(tag() | punct_tag()) + '>"'
    return Cohort(wordform, readings)

def document():
    return lists(cohort(), min_size=1, max_size=5).map(Document)

class TestCG3(TestCase):

    def setUp(self):
        self.applicator = Applicator('test/bm_morf-prestat-unicode.cg')

    @given(document())
    def test_parse(self, doc):
        text = str(doc)

        parsed_doc = str(self.applicator.parse(text))
        self.assertEqual(text, parsed_doc)
