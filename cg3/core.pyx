# Cython bindings to libcg3

cimport cg3.ccore as c

import os

from contextlib import contextmanager
from funcparserlib.lexer import make_tokenizer
from funcparserlib.parser import oneplus, many, some
from libc.stdio cimport FILE, fdopen
from pathlib import Path
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


# Is this class really needed?
cdef class Tag:
    cdef c.cg3_tag* _raw

    @staticmethod
    cdef create(c.cg3_tag* raw):
        tag = Tag()
        tag._raw = raw
        return tag

    def __str__(self):
        cdef bytes string = c.cg3_tag_gettext_u8(self._raw)
        return string.decode()

    def __repr__(self):
        return '<{} "{}">'.format(self.__class__.__name__, str(self))


# The second tag (the first is the cohort name) of a reading is the
# lexeme, the rest are part-of-speech. Should we encode those
# semantics?
cdef class Reading:
    cdef c.cg3_reading* _raw

    @staticmethod
    cdef create(c.cg3_reading* raw):
        reading = Reading()
        reading._raw = raw
        return reading

    def __str__(self):
        # The first tag is the cohort name.
        return ' '.join([str(tag) for tag in self[1:]])

    def __repr__(self):
        return '<{} {}>'.format(self.__class__.__name__, self[1])

    def __len__(self):
        cdef size_t n = c.cg3_reading_numtags(self._raw)
        return n

    # Make it possible to treat Reading as a list.
    def __getitem__(self, key):
        cdef c.cg3_reading* tag
        if isinstance(key, slice):
            l = []
            for i in range(*key.indices(len(self))):
                l.append(self[i])
            return l

        if isinstance(key, int):
            if len(self) <= key:
                raise IndexError('Reading index out of bounds')

            tag = c.cg3_reading_gettag(self._raw, key % len(self))
            return Tag.create(tag)

        raise TypeError(
            'Cohort indices must be a slice or an integer, not {}'.format(type(key))
        )

    def __iter__(self):
        for i in range(len(self)):
            yield self[i]

    def add_tag(self, Tag tag):
        return c.cg3_reading_addtag(self._raw, tag._raw)

    def __dealloc__(self):
        # Freed by the the cohort it belongs to.
        pass


cdef class Cohort:
    cdef c.cg3_cohort* _raw

    @staticmethod
    cdef create(c.cg3_cohort* raw, Tag wordform):
        cohort = Cohort()
        cohort._raw = raw
        c.cg3_cohort_setwordform(raw, wordform._raw)
        return cohort

    def __len__(self):
        cdef size_t n
        n = c.cg3_cohort_numreadings(self._raw)
        return n

    # Make it possible to treat cohort as a list.
    def __getitem__(self, key):
        cdef c.cg3_reading* reading
        if isinstance(key, slice):
            l = []
            for i in range(*key.indices(len(self))):
                l.append(self[i])
            return l

        if isinstance(key, int):
            if len(self) <= key:
                raise IndexError('Cohort index out of bounds')

            reading = c.cg3_cohort_getreading(self._raw, key % len(self))
            return Reading.create(reading)

        raise TypeError(
            'Cohort indices must be integers, not {}'.format(type(key))
        )

    def __str__(self):
        wordform = self.get_wordform()
        readings = ['\t' + str(reading) for reading in self]
        return str(wordform) + '\n' + '\n'.join(readings)

    def __iter__(self):
        for i in range(len(self)):
            yield self[i]

    def __repr__(self):
        return "<{} {}>".format(
            self.__class__.__name__, str(self.get_wordform()))

    def get_wordform(self):
        cdef c.cg3_tag* tag
        tag = c.cg3_cohort_getwordform(self._raw)
        return Tag.create(tag)

    def add_reading(self, Reading reading):
        c.cg3_cohort_addreading(self._raw, reading._raw)

    # When creating a reading it is not automatically added to the
    # cohort. Should we change that here in python?
    def create_reading(self):
        cdef c.cg3_reading* reading
        # Sets the wordform of the cohort as the first tag.
        reading = c.cg3_reading_create(self._raw)
        return Reading.create(reading)

    def __dealloc__(self):
        # Freed by the the document it belongs to.
        pass


cdef class Document:
    cdef c.cg3_sentence* _raw
    # Need to hold onto a reference so the document isn't garbage
    # collected when the applicator goes out of scope.
    cdef Applicator _app

    @staticmethod
    cdef create(c.cg3_sentence* raw, Applicator app):
        document = Document()
        document._raw = raw
        document._app = app
        return document

    def __str__(self):
        # The first cohort is <<<, we don't need that.
        return '\n'.join([str(cohort) for cohort in self[1:]])

    def __len__(self):
        cdef size_t n
        n = c.cg3_sentence_numcohorts(self._raw)
        return n

    # Treat the document as a list of cohorts.
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

    # Created cohorts do not belong to the document and need to be
    # freed manually. Cohorts added to a document is freed by the
    # document.
    def create_cohort(self, Tag wordform):
        cdef c.cg3_cohort* cohort
        cohort = c.cg3_cohort_create(self._raw)
        return Cohort.create(cohort, wordform)

    def __dealloc__(self):
        c.cg3_sentence_free(self._raw)

# As the cg3 library is dependent on some global state, there is a
# case for making this a singlton object. That could also make the
# python api nicer.
cdef class Applicator:
    cdef c.cg3_grammar* _raw_grammar
    cdef c.cg3_applicator* _raw
    cdef str grammar_file

    def __cinit__(self, grammar_file):
        if not Path(grammar_file).is_file():
            raise FileNotFoundError(grammar_file)

        self.grammar_file = grammar_file
        with cg3_error():
            self._raw_grammar = c.cg3_grammar_load(grammar_file.encode())

        with cg3_error():
            self._raw = c.cg3_applicator_create(self._raw_grammar)

        c.cg3_applicator_setflags(self._raw, c.CG3F_NO_PASS_ORIGIN)

    def create_tag(self, text):
        cdef c.cg3_tag* tag
        if not text:
            raise ValueError('Cannot create tag with empty string')
        if '\x00' in text:
            raise ValueError('Cannot create tag that contains "\\x00": {}'.format(repr(text)))
        try:
            tag = c.cg3_tag_create_u8(self._raw, text.encode())
        except TypeError:
            tag = c.cg3_tag_create_u8(self._raw, text)
        return Tag.create(tag)

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

        document = parser.parse(tokens)

        cdef c.cg3_sentence* sentence = c.cg3_sentence_new(self._raw)
        doc = Document.create(sentence, self)

        for wordform, readings in document:
            wordform = self.create_tag(wordform)
            cohort = doc.create_cohort(wordform)

            for lexeme, part_of_speech in readings:
                lexeme = self.create_tag(lexeme)
                reading = cohort.create_reading()
                reading.add_tag(lexeme)
                for pos in part_of_speech:
                    pos = self.create_tag(pos)
                    reading.add_tag(pos)
                cohort.add_reading(reading)
            doc.add_cohort(cohort)

        return doc

    def run_rules(self, Document doc):
        with cg3_error():
            c.cg3_sentence_runrules(self._raw, doc._raw)

    def __dealloc__(self):
        c.cg3_applicator_free(self._raw)
        c.cg3_grammar_free(self._raw_grammar)
