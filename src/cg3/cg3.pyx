# Cython bindings to libcg3

cimport ccg3

from libc.stdint cimport uint32_t
from libc.stdio cimport FILE, fflush, fclose
from re import fullmatch, findall

cdef extern from "memstream/memstream.h" nogil:
    FILE *open_memstream(char **, size_t *)

cdef class Tag:
    cdef ccg3.cg3_tag *_raw_tag

    def __repr__(self):
        text = self.to_string()
        return 'Tag<"{}">'.format(text)

    def to_string(self):
        cdef bytes string = ccg3.cg3_tag_gettext_u8(self._raw_tag)
        return string.decode('UTF-8', 'strict')


cdef class Reading:
    cdef ccg3.cg3_reading *_raw_reading

    def __len__(self):
        cdef size_t n
        n = ccg3.cg3_reading_numtags(self._raw_reading)
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
            tag._raw_tag = ccg3.cg3_reading_gettag(self._raw_reading, key % len(self))
            return tag

        raise TypeError(
            'Cohort indices must be a slice or an integer, not {}'.format(type(key))
        )

    def __iter__(self):
        for i in range(len(self)):
            yield self[i]

    def add_tag(self, Tag tag):
        return ccg3.cg3_reading_addtag(self._raw_reading, tag._raw_tag)


cdef class Cohort:
    cdef ccg3.cg3_cohort *_raw_cohort

    def __len__(self):
        cdef size_t n
        n = ccg3.cg3_cohort_numreadings(self._raw_cohort)
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
            reading._raw_reading = ccg3.cg3_cohort_getreading(
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
        tag._raw_tag = ccg3.cg3_cohort_getwordform(self._raw_cohort)
        return tag

    def add_reading(self, Reading reading):
        ccg3.cg3_cohort_addreading(self._raw_cohort, reading._raw_reading)

    def create_reading(self):
        cdef Reading reading = Reading()
        reading._raw_reading = ccg3.cg3_reading_create(self._raw_cohort)
        return reading


cdef class Document:
    cdef ccg3.cg3_sentence *_raw_doc

    def __cinit__(self, Applicator applicator):
        self._raw_doc = ccg3.cg3_sentence_new(applicator._raw_applicator)

    def __len__(self):
        cdef size_t n
        n = ccg3.cg3_sentence_numcohorts(self._raw_doc)
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
            cohort._raw_cohort = ccg3.cg3_sentence_getcohort(
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
        ccg3.cg3_sentence_addcohort(self._raw_doc, cohort._raw_cohort)

    def create_cohort(self, Tag wordform):
        cdef Cohort cohort = Cohort()
        cohort._raw_cohort = ccg3.cg3_cohort_create(self._raw_doc)
        ccg3.cg3_cohort_setwordform(cohort._raw_cohort, wordform._raw_tag)
        return cohort

    def __dealloc__(self):
        ccg3.cg3_sentence_free(self._raw_doc)


cdef class MemFile:
    cdef char *buf
    cdef size_t size
    cdef FILE *fd

    def __cinit__(self):
        self.buf = ""
        self.size = 0
        self.fd = open_memstream(&self.buf, &self.size)

    cdef to_string(self):
        fflush(self.fd)
        try:
            return self.buf.decode('UTF-8', 'strict')
        finally:
            self.buf = ""
            self.size = 0
            fclose(self.fd)
            self.fd = open_memstream(&self.buf, &self.size)

    def __dealloc__(self):
        fclose(self.fd)


cdef class Applicator:
    cdef ccg3.cg3_grammar *_raw_grammar
    cdef ccg3.cg3_applicator *_raw_applicator

    cdef MemFile _stdin
    cdef MemFile _stdout
    cdef MemFile _stderr

    def __cinit__(self, grammar_file):
        self._stdin = MemFile()
        self._stdout = MemFile()
        self._stderr = MemFile()
        try:
            if not self.cg3_init():
                raise Exception('Error on initializing cg3')

            f = grammar_file.encode('UTF-8')
            self._raw_grammar = ccg3.cg3_grammar_load(f)
            error_msg = self._stderr.to_string()
            if error_msg.startswith('CG3 Error:'):
                raise Exception(error_msg)

            self._raw_applicator = ccg3.cg3_applicator_create(self._raw_grammar)
            error_msg = self._stderr.to_string()
            if error_msg.startswith("CG3 Error:"):
                raise Exception(error_msg)

            self.set_flags(ccg3.CG3F_NO_PASS_ORIGIN)
        finally:
            ccg3.cg3_cleanup()

    def cg3_init(self):
        return ccg3.cg3_init(
            self._stdin.fd,
            self._stdout.fd,
            self._stderr.fd
        )

    def create_tag(self, text):
        cdef Tag tag = Tag()
        try:
            tag._raw_tag = ccg3.cg3_tag_create_u8(self._raw_applicator, text.encode('UTF-8'))
        except TypeError:
           tag._raw_tag = ccg3.cg3_tag_create_u8(self._raw_applicator, text)
        return tag

    def set_flags(self, uint32_t flags):
        ccg3.cg3_applicator_setflags(self._raw_applicator, flags)

    def parse(self, f):
        try:
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
                            error_msg = self._stderr.to_string()
                            raise Exception(error_msg)
                line = f.readline().strip()
            return doc
        finally:
            ccg3.cg3_cleanup()

    def run_rules(self, Document doc):
        try:
            self.cg3_init()
            ccg3.cg3_sentence_runrules(self._raw_applicator, doc._raw_doc)
            for cohort in doc:
                for reading in cohort:
                    print(reading[0].to_string())
                    tags = [tag.to_string() for tag in reading[1:]]
                    print('\t' + ' '.join(tags))
        finally:
            ccg3.cg3_cleanup()

    def __dealloc__(self):
        ccg3.cg3_applicator_free(self._raw_applicator)
        ccg3.cg3_grammar_free(self._raw_grammar)
