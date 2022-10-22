import logging
import argparse
from collections import defaultdict


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


class Node:
    next_id = 0

    def __init__(self, prob=0.0, parent=None):
        self.prob = prob
        self.tot_prob = None
        self.children = []
        self.parent = parent
        self.id = Node.next_id
        Node.next_id += 1
        if parent is not None:
            parent.add_child(self)

    def add_child(self, child):
        self.children.append(child)
    
    def validate_children(self):
        assert abs(sum([c.prob for c in self.children]) - 1) < 1e-6

    def my_tot_prob(self, recompute=False):
        if not recompute and self.tot_prob is not None:
            return self.tot_prob

        tot_prob = self.prob
        parent = self.parent
        while parent is not None:
            tot_prob *= parent.prob
            parent = parent.parent
        self.tot_prob = tot_prob
        return tot_prob
    
    def print_as_str(self):
        if self.tot_prob is None:
            self.my_tot_prob()
        parent = self.parent.id if self.parent is not None else None
        children = [c.id for c in self.children]
        print(f"{self.id}, p={self.prob}, tot_p={self.tot_prob}, parent={parent}, children={children}")


def main(opts):
    root = Node(prob=1.0, parent=None)
    
    c = Node(prob=0.2, parent=root)
    for p in [0.6, 0.25, 0.15]:
        cc = Node(prob=p, parent=c)
    
    c = Node(prob=0.3, parent=root)
    for p in [0.9, 0.1]:
        cc = Node(prob=p, parent=c)
    
    c = Node(prob=0.5, parent=root)
    for p in [0.3, 0.2, 0.5]:
        cc = Node(prob=p, parent=c)
    
    node_list = [root]
    while len(node_list) > 0:
        n = node_list.pop()
        
        # do something
        n.print_as_str()

        for child in n.children:
            node_list.append(child)

    leaves = []
    node_list = [root]
    while len(node_list) > 0:
        n = node_list.pop()
        
        # do something
        if len(n.children) == 0:
            leaves.append(n)

        for child in n.children:
            node_list.append(child)

    print("Ordered sample without replacement from leaves as a categorical distribution:")
    sum_p = 0
    pairs = []
    unordered_pairs = defaultdict(int)
    for a in leaves:
        left_over_prob = 1 - a.my_tot_prob()
        for b in leaves:
            if b == a:
                continue

            p = a.my_tot_prob() * b.my_tot_prob() / left_over_prob
            sum_p += p

            # print(f"{a.id}_{b.id}: {p}")

            pairs.append((p, (a.id, b.id)))

            upair = (a.id, b.id)
            if a.id > b.id:
                upair = (b.id, a.id)
            unordered_pairs[upair] += p
    assert abs(sum_p - 1) < 1e-6
    # for s in sorted(pairs, key=lambda x: x[0]):
    #     f"{a.id}_{b.id}"
    #     print(f"{s[1]}: {s[0]}")
    for upair, p in sorted(unordered_pairs.items(), key=lambda x: x[1]):
        print(f"{upair}: {p}")

    print("Ordered sample without replacement in a top down manner:")
    pass                


if __name__ == '__main__':
    opts = parse_opts()

    main(opts)
