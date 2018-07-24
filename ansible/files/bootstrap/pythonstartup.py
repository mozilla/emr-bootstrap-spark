"""
This file is intended to be set as the PYTHONSTARTUP environment variable.

The pyspark executable sets its own python startup that sets up spark and sc,
and then executes the file specified by PYTHONSTARTUP if it exists,
so we should have access to sc by the time this runs.
"""

import sys

try:
    sc
except NameError:
    # sc isn't defined, so this must be a normal python session; nothing to do.
    pass
else:
    # Workaround for EMR bug; when the --packages arg is specified to pyspark,
    # the path that ends up in spark.submit.pyFiles is valid,
    # but not the one on sys.path (at least on the master node);
    # we make sure all the entries on pyFiles end up on sys.path.
    for p in str(sc.getConf().get(u'spark.submit.pyFiles')).split(','):
        if p not in sys.path:
            sys.path.append(p)
