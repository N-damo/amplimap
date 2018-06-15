#!/usr/bin/env python
import os
import sys

import snakemake
import argparse
import yaml

from .version import __title__, __version__


def main(argv = None):
    """
    Run amplimap.
    """
    try:
        basedir = os.path.dirname(os.path.realpath(__file__))
        
        #parse the arguments, which will be available as properties of args (e.g. args.probe)
        parser = argparse.ArgumentParser(
            description = "amplimap v{} setup wizard".format(__version__),
            formatter_class = argparse.ArgumentDefaultsHelpFormatter)

        #specify parameters
        parser.add_argument("--debug", help="debug mode", action="store_true")
        if argv is None:
            args = parser.parse_args()
        else:
            args = parser.parse_args(argv)

        raise Exception('Not implemented yet.')
        
    except Exception as e:
        if args.debug:
            import traceback
            traceback.print_exc()
        sys.stderr.write('\nERROR: {}\n\n'.format(e))
        sys.stderr.write('{} {} failed!\n'.format(__title__, __version__))
        return 1

if __name__ == '__main__':
    sys.exit(main())
