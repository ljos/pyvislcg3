# Cython bindings to libcg3

import os

cimport cg3.ccore as c

from contextlib import contextmanager
from funcparserlib.lexer import make_tokenizer
from funcparserlib.parser import oneplus, many, some
from libc.stdio cimport FILE, fdopen
from re import fullmatch, findall
from tempfile import mkstemp

# We are using a context manager instead of a decorator because cython
# functions and methods can't have python decorators without having
# trouble with the return type.
@contextmanager
def cg3_error():
    cdef FILE* f
    try:
        fd, path = mkstemp()
        f = fdopen(fd, 'w')

        # We only need one FILE object as it is only the error one
        # that is used.
        if not c.cg3_init(f, f, f):
            # Cleanup first so the file is closed and we can open it
            # in python.
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


# Is this class really needed?
cdef class Tag:
    cdef c.cg3_tag* _raw

    def __str__(self):
        cdef bytes string = c.cg3_tag_gettext_u8(self._raw)
        return string.decode()

    def __repr__(self):
        return 'Tag<"{}">'.format(str(self))


# The first tag of a reading is the lexeme, the rest are
# part-of-speech. Should we encode those semantics?
cdef class Reading:
    cdef c.cg3_reading* _raw

    def __len__(self):
        cdef size_t n = c.cg3_reading_numtags(self._raw)
        return n

    def __getitem__(self, key):
        cdef Tag tag
        if isinstance(key, slice):
            l = []
            for i in range(*key.indices(len(self))):
                l.append(self[i])
            return l

        if isinstance(key, int):
            if len(self) <= key:
                raise IndexError('Reading index out of bounds')

            tag = Tag()
            tag._raw = c.cg3_reading_gettag(self._raw, key % len(self))
            return tag

        raise TypeError(
            'Cohort indices must be a slice or an integer, not {}'.format(type(key))
        )

    def __iter__(self):
        for i in range(len(self)):
            yield self[i]

    def add_tag(self, Tag tag):
        return c.cg3_reading_addtag(self._raw, tag._raw)


cdef class Cohort:
    cdef c.cg3_cohort* _raw

    def __len__(self):
        cdef size_t n
        n = c.cg3_cohort_numreadings(self._raw)
        return n

    def __getitem__(self, key):
        cdef Reading reading
        if isinstance(key, slice):
            l = []
            for i in range(*key.indices(len(self))):
                l.append(self[i])
            return l

        if isinstance(key, int):
            if len(self) <= key:
                raise IndexError('Cohort index out of bounds')

            reading = Reading()
            reading._raw = c.cg3_cohort_getreading(
                self._raw,
                key % len(self)
            )
            return reading

        raise TypeError(
            'Cohort indices must be integers, not {}'.format(type(key))
        )

    def __iter__(self):
        for i in range(len(self)):
            yield self[i]

    def __repr__(self):
        return "Cohort({})".format(str(self.get_wordform()))

    def get_wordform(self):
        cdef Tag tag = Tag()
        tag._raw = c.cg3_cohort_getwordform(self._raw)
        return tag

    def set_wordform(self, Tag wordform):
        c.cg3_cohort_setwordform(self._raw, wordform._raw)

    def add_reading(self, Reading reading):
        c.cg3_cohort_addreading(self._raw, reading._raw)

    # When creating a reading it is not automatically added to the
    # cohort. Should we change that here in python?
    def create_reading(self):
        cdef Reading reading = Reading()
        reading._raw = c.cg3_reading_create(self._raw)
        return reading


cdef class Document:
    cdef c.cg3_sentence* _raw

    def __cinit__(self, Applicator applicator):
        self._raw = c.cg3_sentence_new(applicator._raw)

    def __len__(self):
        cdef size_t n
        n = c.cg3_sentence_numcohorts(self._raw)
        return n

    def __getitem__(self, key):
        cdef Cohort cohort

        if isinstance(key, slice):
            l = []
            for i in range(*key.indices(len(self))):
                l.append(self[i])
            return l

        if isinstance(key, int):
            if len(self) <= key:
                raise IndexError('Document index out of bounds')

            cohort = Cohort()
            cohort._raw = c.cg3_sentence_getcohort(self._raw, key % len(self))
            return cohort

        raise TypeError(
            'Document indices must be integers, not {}'.format(type(key))
        )

    def __iter__(self):
        for i in range(len(self)):
            yield self[i]

    def add_cohort(self, Cohort cohort):
        c.cg3_sentence_addcohort(self._raw, cohort._raw)

    def create_cohort(self, Tag wordform):
        cdef Cohort cohort = Cohort()
        cohort._raw = c.cg3_cohort_create(self._raw)
        cohort.set_wordform(wordform)
        return cohort

# As the cg3 library is dependent on some global state, there is a
# case for making this a singlton object. That could also make the
# python api nicer.
cdef class Applicator:
    cdef c.cg3_applicator* _raw

    def __cinit__(self, grammar_file):
        cdef c.cg3_grammar* grammar

        with cg3_error():
            grammar = c.cg3_grammar_load(grammar_file.encode())

        with cg3_error():
            self._raw = c.cg3_applicator_create(grammar)

        c.cg3_applicator_setflags(self._raw, c.CG3F_NO_PASS_ORIGIN)

    def create_tag(self, text):
        cdef Tag tag = Tag()
        try:
            tag._raw = c.cg3_tag_create_u8(self._raw, text.encode())
        except TypeError:
           tag._raw = c.cg3_tag_create_u8(self._raw, text)
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
        cohort = toktype('Cohort') + oneplus(reading)
        sentence = many(cohort)

        document = sentence.parse(tokens)

        doc = Document(self)

        for cohort in document:
            wordform, *readings = cohort
            wordform = self.create_tag(wordform)
            cohort = doc.create_cohort(wordform)
            for pos in readings:
                reading = cohort.create_reading()
                for p in pos:
                    p = self.create_tag(p)
                    reading.add_tag(p)
                cohort.add_reading(reading)
            doc.add_cohort(cohort)

        return doc

    def run_rules(self, Document doc):
        c.cg3_sentence_runrules(self._raw, doc._raw)
        # The first cohort is <<<, we don't need that.
        for cohort in doc[1:]:
            for reading in cohort:
                head, *reading = reading
                print(str(head))
                print('\t' + ' '.join([str(tag) for tag in reading]))

    def __dealloc__(self):
        c.cg3_applicator_free(self._raw)
