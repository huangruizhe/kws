import logging
import argparse

logging.basicConfig(
    format = "%(asctime)s - %(levelname)s - %(funcName)s:%(lineno)d - %(message)s",
    level = 10
)

def parse_opts():
    parser = argparse.ArgumentParser(
        description='',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    parser.add_argument('--fsts', type=str, default=None, help='')
    parser.add_argument('--eps2', type=int, help='')

    opts = parser.parse_args()
    return opts


def main(opts):

    def proc_fst(uid, fst):
        if uid is None:
            return
        print(uid)
        print('\t'.join(fst[0]))
        for l in fst[1:-1]:
            print(f"{l[0]}\t{l[0]}\t{0}\t{opts.eps2}")
            print('\t'.join(l))
        print(fst[-1])
        print()

    with open(opts.fsts, 'r') as fin:
        uid = None
        fst = list()
        for line in fin:
            line = line.strip()
            
            # logging.info(line)
            if len(line) == 0:
                proc_fst(uid, fst)
                uid = None
                fst = list()
                continue
            
            fields = line.split()
            if uid is None:
                if len(fields) != 1:
                    logging.error(line)
                assert len(fields) == 1
                uid = line
            elif len(fields) > 1:
                fst.append(fields)
            elif len(fields) == 1:
                assert line.isdigit()
                fst.append(line)
            else:
                logging.error("Cannot reach here!")
                exit(1)

        proc_fst(uid, fst)        
            


if __name__ == '__main__':
    opts = parse_opts()

    main(opts)
