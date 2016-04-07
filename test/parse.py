from cg3 import Applicator

if __name__ == '__main__':
    applicator = Applicator('test/bm_morf-prestat-unicode.cg')
    with open('test/test.cg') as f:
        document = applicator.parse(f)
    document = applicator.run_rules(document)
    print(document)
