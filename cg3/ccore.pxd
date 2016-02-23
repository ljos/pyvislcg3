from libc.stdio cimport FILE
from libc.stdint cimport uint32_t

cdef extern from "cg3.h":
    ctypedef void cg3_grammar
    ctypedef void cg3_applicator
    ctypedef void cg3_sentence
    ctypedef void cg3_cohort
    ctypedef void cg3_reading
    ctypedef void cg3_tag

    ctypedef enum cg3_flags:
        CG3F_ORDERED            = 1 <<  0
        CG3F_UNSAFE             = 1 <<  1
        CG3F_NO_MAPPINGS        = 1 <<  2
        CG3F_NO_CORRECTIONS     = 1 <<  3
        CG3F_NO_BEFORE_SECTIONS = 1 <<  4
        CG3F_NO_SECTIONS        = 1 <<  5
        CG3F_NO_AFTER_SECTIONS  = 1 <<  6
        CG3F_TRACE              = 1 <<  7
        CG3F_SINGLE_RUN         = 1 <<  8
        CG3F_ALWAYS_SPAN        = 1 <<  9
        CG3F_DEP_ALLOW_LOOPS    = 1 << 10
        CG3F_DEP_NO_CROSSING    = 1 << 11
        CG3F_NO_PASS_ORIGIN     = 1 << 13

    ctypedef enum cg3_option:
        CG3O_SECTIONS      = 1
        CG3O_SECTIONS_TEXT = 2

    bint cg3_init(FILE *inp, FILE *out, FILE *err)
    bint cg3_cleanup()

    cg3_grammar *cg3_grammar_load(const char *filename)
    void cg3_grammar_free(cg3_grammar *grammar)

    cg3_applicator *cg3_applicator_create(cg3_grammar *grammar)
    void cg3_applicator_setflags(cg3_applicator *applicator, uint32_t flags)
    void cg3_applicator_setoption(cg3_applicator *applicator, cg3_option option, void *value)
    void cg3_sentence_runrules(cg3_applicator *applicator, cg3_sentence *sentence)
    void cg3_applicator_free(cg3_applicator *applicator)

    cg3_sentence *cg3_sentence_new(cg3_applicator *applicator)
    cg3_sentence *cg3_sentence_copy(cg3_sentence *old, cg3_applicator *new)

    void cg3_sentence_addcohort(cg3_sentence *sentence, cg3_cohort *cohort)
    size_t cg3_sentence_numcohorts(cg3_sentence *sentence)
    cg3_cohort *cg3_sentence_getcohort(cg3_sentence *sentence, size_t which)
    void cg3_sentence_free(cg3_sentence *sentence)
    cg3_cohort *cg3_cohort_create(cg3_sentence *sentence)

    void cg3_cohort_setwordform(cg3_cohort *cohort, cg3_tag *wordform)
    cg3_tag *cg3_cohort_getwordform(cg3_cohort *cohort)
    uint32_t cg3_cohort_getid(cg3_cohort *cohort)
    void cg3_cohort_setdependency(cg3_cohort *cohort, uint32_t dep_self, uint32_t dep_parent)
    void cg3_cohort_getdependency(cg3_cohort *cohort, uint32_t *dep_self, uint32_t *dep_parent)
    void cg3_cohort_addreading(cg3_cohort *cohort, cg3_reading *reading)
    size_t cg3_cohort_numreadings(cg3_cohort *cohort)
    cg3_reading *cg3_cohort_getreading(cg3_cohort *cohort, size_t which)
    void cg3_cohort_free(cg3_cohort *cohort)
    cg3_reading *cg3_reading_create(cg3_cohort *cohort)

    bint cg3_reading_addtag(cg3_reading *reading, cg3_tag *tag)
    size_t cg3_reading_numtags(cg3_reading *reading)
    cg3_tag *cg3_reading_gettag(cg3_reading *reading, size_t which)
    size_t cg3_reading_numtraces(cg3_reading *reading)
    uint32_t cg3_reading_gettrace(cg3_reading *reading, size_t which)
    void cg3_reading_free(cg3_reading *reading)
    cg3_reading *cg3_subreading_create(cg3_reading *reading)
    bint cg3_reading_setsubreading(cg3_reading *reading, cg3_reading *subreading)
    size_t cg3_reading_numsubreadings(cg3_reading *reading)
    cg3_reading *cg3_reading_getsubreading(cg3_reading *reading, size_t which)
    void cg3_subreading_free(cg3_reading *subreading)

    # cg3_tag *cg3_tag_create_u(cg3_applicator *applicator, const UChar *text)
    cg3_tag *cg3_tag_create_u8(cg3_applicator *applicator, char *text)
    # cg3_tag *cg3_tag_create_u16(cg3_applicator *applicator, const uint16_t *text)
    # cg3_tag *cg3_tag_create_u32(cg3_applicator *applicator, const uint32_t *text)
    # cg3_tag *cg3_tag_create_w(cg3_applicator *applicator, const wchar_t *text)

    const char *cg3_tag_gettext_u8(cg3_tag *tag)
    # const UChar *cg3_tag_gettext_u(cg3_tag *tag)
