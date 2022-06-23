#!/usr/bin/env python3

import sys
import os
import argparse
import logging
import tqdm
import gzip
from collections import defaultdict, Counter
import nltk
from nltk.collocations import *

# https://www.geeksforgeeks.org/python-import-from-parent-directory/
current = os.path.dirname(os.path.realpath(__file__))
parent = os.path.dirname(current)
sys.path.append(parent)
# print(parent)

from utils.utils import *



