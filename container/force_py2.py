import sys
import os

if __name__ == '__main__':
    argv = sys.argv
    path, _ = os.path.split(argv[0])
    argv[0] = os.path.join(path, 'build_tar.py')
    argv = ['/usr/bin/env', 'python2'] + argv
    os.execv(argv[0], argv)
