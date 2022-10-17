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

    parser.add_argument('--nbest', type=int, default=-1, help='how many best results (for each KWID) should be printed (int, default -1, i.e. no limit')
    parser.add_argument('--duptime', type=int, default=50, help='duplicates detection, tolerance (in frames) for being the same hits (int,  default = 50)')
    parser.add_argument('--likes', default=False, action='store_true', help='The smaller the score, the better')
    parser.add_argument('--probs', default=True, action='store_true', help='The bigger the score, the better')

    opts = parser.parse_args()
    return opts


def main(opts):
    pass


if __name__ == '__main__':
    opts = parse_opts()

    main(opts)
