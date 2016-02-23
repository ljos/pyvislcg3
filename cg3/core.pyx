# Cython bindings to libcg3

cimport cg3.ccore as c

from libc.stdio cimport FILE, fdopen
from re import fullmatch, findall
from io import BytesIO

cdef class Tag:
    cdef c.cg3_tag *_raw_tag

    def __repr__(self):
        text = self.to_string()
        return 'Tag<"{}">'.format(text)

    def __str__(self):
        cdef bytes string = c.cg3_tag_gettext_u8(self._raw_tag)
        return string.decode()


cdef class Reading:
    cdef c.cg3_reading *_raw_reading

    def __len__(self):
        cdef size_t n = c.cg3_reading_numtags(self._raw_reading)
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
            tag._raw_tag = c.cg3_reading_gettag(self._raw_reading, key % len(self))
            return tag

        raise TypeError(
            'Cohort indices must be a slice or an integer, not {}'.format(type(key))
        )

    def __iter__(self):
        for i in range(len(self)):
            yield self[i]

    def add_tag(self, Tag tag):
        return c.cg3_reading_addtag(self._raw_reading, tag._raw_tag)


cdef class Cohort:
    cdef c.cg3_cohort *_raw_cohort

    def __len__(self):
        cdef size_t n
        n = c.cg3_cohort_numreadings(self._raw_cohort)
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
            reading._raw_reading = c.cg3_cohort_getreading(
                self._raw_cohort,
                key % len(self)
            )
            return reading

        raise TypeError(
            'Cohort indices must be integers, not {}'.format(type(key))
        )

    def __iter__(self):
        for i in range(len(self)):
            yield self[i]

    def get_wordform(self):
        cdef Tag tag = Tag()
        tag._raw_tag = c.cg3_cohort_getwordform(self._raw_cohort)
        return tag

    def add_reading(self, Reading reading):
        c.cg3_cohort_addreading(self._raw_cohort, reading._raw_reading)

    def create_reading(self):
        cdef Reading reading = Reading()
        reading._raw_reading = c.cg3_reading_create(self._raw_cohort)
        return reading


cdef class Document:
    cdef c.cg3_sentence *_raw_doc

    def __cinit__(self, Applicator applicator):
        self._raw_doc = c.cg3_sentence_new(applicator._raw_applicator)

    def __len__(self):
        cdef size_t n
        n = c.cg3_sentence_numcohorts(self._raw_doc)
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
            cohort._raw_cohort = c.cg3_sentence_getcohort(
                self._raw_doc,
                key % len(self)
            )
            return cohort

        raise TypeError(
            'Document indices must be integers, not {}'.format(type(key))
        )

    def __iter__(self):
        for i in range(len(self)):
            yield self[i]

    def add_cohort(self, Cohort cohort):
        c.cg3_sentence_addcohort(self._raw_doc, cohort._raw_cohort)

    def create_cohort(self, Tag wordform):
        cdef Cohort cohort = Cohort()
        cohort._raw_cohort = c.cg3_cohort_create(self._raw_doc)
        c.cg3_cohort_setwordform(cohort._raw_cohort, wordform._raw_tag)
        return cohort

    def __dealloc__(self):
        c.cg3_sentence_free(self._raw_doc)


cdef class Applicator:
    cdef c.cg3_grammar *_raw_grammar
    cdef c.cg3_applicator *_raw_applicator

    def __cinit__(self, grammar_file):
        self._stdin = BytesIO()
        self._stdout = BytesIO()
        self._stderr = BytesIO()

        cdef FILE *fd_in = fdopen(self._stdin.fileno(), 'w')
        cdef FILE *fd_out = fdopen(self._stdout.fileno(), 'w')
        cdef FILE *fd_err = fdopen(self._stderr.fileno(), 'w')

        success = c.cg3_init(fd_in, fd_out, fd_err)
        if not success:
            raise Exception('Failed initializing cg3')

        f = grammar_file.encode()
        self._raw_grammar = c.cg3_grammar_load(f)
        error_msg = self._stderr.readall().decode()
        if error_msg.startswith('CG3 Error:'):
            raise Exception(error_msg)

        self._raw_applicator = c.cg3_applicator_create(self._raw_grammar)
        error_msg = self._stderr.readall().decode()
        if error_msg.startswith("CG3 Error:"):
            raise Exception(error_msg)

        c.cg3_applicator_setflags(self._raw_applicator, c.CG3F_NO_PASS_ORIGIN)

    def create_tag(self, text):
        cdef Tag tag = Tag()
        try:
            tag._raw_tag = c.cg3_tag_create_u8(
                self._raw_applicator,
                text.encode()
            )
        except TypeError:
           tag._raw_tag = c.cg3_tag_create_u8(self._raw_applicator, text)
        return tag

    def parse(self, f):
        self.cg3_init()
        doc = Document(self)
        line = f.readline().strip()
        while line:
            if fullmatch(r'"<[^>]*>"', line):
                tag = self.create_tag(line)
                cohort = doc.create_cohort(tag)
                doc.add_cohort(cohort)
            elif line:
                reading = cohort.create_reading()
                cohort.add_reading(reading)
                for tag in findall(r'\S+', line):
                    tag = self.create_tag(tag)
                    if not reading.add_tag(tag):
                        error_msg = self._stderr.readall().decode()
                        raise Exception(error_msg)
            line = f.readline().strip()
        return doc

    def run_rules(self, Document doc):
        self.cg3_init()
        c.cg3_sentence_runrules(self._raw_applicator, doc._raw_doc)
        for cohort in doc:
            for reading in cohort:
                print(str(reading[0]))
                tags = [str(tag) for tag in reading[1:]]
                print('\t' + ' '.join(tags))

    def __dealloc__(self):
        c.cg3_cleanup()
        c.cg3_applicator_free(self._raw_applicator)
        c.cg3_grammar_free(self._raw_grammar)
