import sys
import os
import tqdm
import gzip
import logging

logging.basicConfig(
    format = "%(asctime)s — %(levelname)s — %(funcName)s:%(lineno)d — %(message)s", 
    level = 10
)


def get_files_in_dir(dir):
    return os.listdir()


def get_files(pattern):
    from glob import glob
    return glob(pattern)


def read_multiple_files(files, encoding, fn=lambda x: x.split()):
    import fileinput as fi

    lines = []    
    total_size = sum([get_file_size(f) for f in files])
    with tqdm.tqdm(total=total_size) as pbar:
        with fi.input(files=files) as fin:
            for line in fin:
                if fin.isfirstline():
                    logging.info(f'> Start to read {fin.filename()}')
                pbar.update(len(line))
                line = line.strip()
                if len(line) == 0:
                    continue
                line = fn(line)
                if line is not None:
                    lines.append(line)
    return lines


def open_file(filename, mode="rt", encoding="utf-8"):
    if filename.endswith(".gz"):
        return gzip.open(filename, mode=mode, encoding=encoding)
    else:
        return open(filename, mode=mode, encoding=encoding)


def get_file_size(filename):
    import subprocess
    import re

    if filename.endswith(".gz"):
        rs = subprocess.getoutput("gzip -l %s" % filename)
        m = re.search(r"\n\s+\d+\s+(\d+)", rs)
        return int(m.group(1)) if m else -1
    else:
        return os.path.getsize(filename)


def get_file_size_lines(filename):
    with open_file(filename) as fin:
        return len(fin.readlines())


def check_dir(path, create=False):
    """Check if a directory exists."""
    if not os.path.isdir(path):
        if create:
            try:
                os.makedirs(path)
                return True
            except:
                logging.info(f"Please check if {str(path)} exits")
                exit(1)
        else:
            print("ERROR: Directory does not exist: %s" % str(path))
            exit(1)
    else:
        return True
        
