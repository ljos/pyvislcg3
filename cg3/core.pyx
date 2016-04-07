""" Cython bindings to libcg3 """

cimport cg3.ccore as c

import os

from contextlib import contextmanager
from funcparserlib.lexer import make_tokenizer
from funcparserlib.parser import oneplus, many, some
from libc.stdio cimport FILE, fdopen
from pathlib import Path
from re import fullmatch, findall
from tempfile import mkstemp


# This class is basically just so that we have an easy way to
# serialize the document to a string.
class Document:

    def __init__(self, doc):
        self.doc = doc

    def __iter__(self):
        return iter(self.doc)

    def __str__(self):
        output = []
        for cohort, readings in self.doc:
            output.append(cohort)
            for lexeme, part_of_speech in readings:
                output.append('\t{} {}'.format(lexeme, ' '.join(part_of_speech)))
        return '\n'.join(output)


# We are using a context manager instead of a decorator because cython
# functions and methods can't have python decorators without having
# trouble with the return type.
@contextmanager
def cg3_error():
    cdef FILE* f
    try:
        fd, path = mkstemp()
        f = fdopen(fd, 'w')


        # We only need one FILE object as cg3 only prints to the error
        # file.
        if not c.cg3_init(f, f, f):
            # Cleanup before looking for error so the file is closed
            # and we can open it back up again in python.
            c.cg3_cleanup()
            with open(path) as err:
                error_msg = err.readline()
                raise Exception(error_msg)

        yield

        c.cg3_cleanup()
        with open(path) as err:
            error_msg = err.readline()
            # CG3 also reports warnings, so we need to check if it
            # really is a error that we are recieving. It would be
            # better if we could check the if return from CG3 is
            # NULL, but I don't know how to do that with a context
            # manager.
            if error_msg.startswith('CG3 Error:'):
                raise Exception(error_msg)
    finally:
        # Remove the file from the OS.
        os.remove(path)


cdef class Grammar:
    cdef c.cg3_grammar* _raw
    cdef str grammar_file

    def __cinit__(self, str grammar_file):
        if not Path(grammar_file).is_file():
            raise FileNotFoundError(grammar_file)
        self.grammar_file = grammar_file
        with cg3_error():
            self._raw = c.cg3_grammar_load(grammar_file.encode())

    def __repr__(self):
        return '<{} file: {}>'.format(
            self.__class__.__name__, self.grammar_file)

    cdef c.cg3_applicator* _create_applicator(self):
        with cg3_error():
            return c.cg3_applicator_create(self._raw)

    def __dealloc__(self):
        c.cg3_grammar_free(self._raw)


cdef class Applicator:
    cdef Grammar _grammar
    cdef c.cg3_applicator* _raw
    cdef str grammar_file

    def __cinit__(self, grammar_file):
        if not Path(grammar_file).is_file():
            raise FileNotFoundError(grammar_file)

        self._grammar = Grammar(grammar_file)

        self._raw = self._grammar._create_applicator()
        c.cg3_applicator_setflags(self._raw, c.CG3F_NO_PASS_ORIGIN)

    cdef c.cg3_tag* create_tag(self, text):
        cdef c.cg3_tag* tag
        if not text:
            raise ValueError('Cannot create tag with empty string')
        if '\x00' in text:
            raise ValueError('Cannot create tag that contains "\\x00": {}'.format(repr(text)))
        try:
            tag = c.cg3_tag_create_u8(self._raw, text.encode())
        except TypeError:
            tag = c.cg3_tag_create_u8(self._raw, text)
        return tag

    def parse(self, f):
        def tokenize(string):
            specs = [
                ('Word', (r'<word>.+</word>',)),
                ('Cohort', (r'"<[^>]+>"',)),
                ('Reading', (r'"[^"]+"',)),
                ('Space', (r'\s+',)),
                ('NL', (r'[\r\n]+',)),
                ('PoS', (r'\S+',))
            ]
            useless = ['NL', 'Space', 'Word']
            t = make_tokenizer(specs)
            return [x for x in t(string) if x.type not in useless]

        tokens = tokenize(f.read())

        tokval = lambda x: x.value
        toktype = lambda t: some(lambda x: x.type == t) >> tokval

        pos = toktype('PoS')
        reading = toktype('Reading') + many(pos)
        cohort = toktype('Cohort') + many(reading)
        parser = many(cohort)

        # Output looks like
        # [('"<Cohort">', [('"Lexeme"', ['PoS', ...]), ...]) ...]
        doc = parser.parse(tokens)

        return Document(doc)


    def run_rules(self, doc):
        cdef c.cg3_sentence* window
        cdef c.cg3_tag* tag
        cdef c.cg3_cohort* cohort
        cdef c.cg3_reading* reading

        try:
            # Read document to c structure.
            window = c.cg3_sentence_new(self._raw)
            for wordform, readings in doc:
                tag = self.create_tag(wordform)
                cohort = c.cg3_cohort_create(window)
                c.cg3_cohort_setwordform(cohort, tag)

                for lexeme, part_of_speech in readings:
                    tag = self.create_tag(lexeme)
                    reading = c.cg3_reading_create(cohort)
                    c.cg3_reading_addtag(reading, tag)

                    for pos in part_of_speech:
                        tag = self.create_tag(pos)
                        c.cg3_reading_addtag(reading, tag)

                    c.cg3_cohort_addreading(cohort, reading)
                c.cg3_sentence_addcohort(window, cohort)

            # Run constraint grammar rules.
            with cg3_error():
                c.cg3_sentence_runrules(self._raw, window)

            # Convert document back to python structure.
            doc = []
            n = c.cg3_sentence_numcohorts(window)
            # The first cohort is >>>, we don't need that.
            for i in range(1, n):
                cohort = c.cg3_sentence_getcohort(window, i)
                n = c.cg3_cohort_numreadings(cohort)
                readings = []
                for j in range(n):
                    reading = c.cg3_cohort_getreading(cohort, j)
                    n = c.cg3_reading_numtags(reading)

                    part_of_speech = []
                    # The first one is the cohort name, the second the
                    # lexeme.
                    for k in range(2, n):
                        tag = c.cg3_reading_gettag(reading, k)
                        name = c.cg3_tag_gettext_u8(tag).decode()
                        part_of_speech.append(name)

                    tag = c.cg3_reading_gettag(reading, 1)
                    name = c.cg3_tag_gettext_u8(tag).decode()
                    readings.append((name, part_of_speech))

                tag = c.cg3_cohort_getwordform(cohort)
                name = c.cg3_tag_gettext_u8(tag).decode()
                doc.append((name, readings))

            return Document(doc)
        finally:
            c.cg3_sentence_free(window)


    def __dealloc__(self):
        c.cg3_applicator_free(self._raw)
