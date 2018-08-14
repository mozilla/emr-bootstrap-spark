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
    # Workaround for EMR-specific behavior;
    # when the --packages arg is specified to pyspark,
    # the path that ends up in spark.submit.pyFiles is valid,
    # but not the one on sys.path (at least on the master node);
    # we make sure all the entries on pyFiles end up on sys.path.
    #
    # See our case with AWS in the cloudservices-aws-dev account:
    # https://console.aws.amazon.com/support/v1?region=us-west-2#/case/?displayId=5170206571&language=en
    #
    # This bug is fixed in EMR 5.16, so we can remove this entire file
    # and its usage in telemetry.sh once our minimum supported EMR version
    # is 5.16+.
    for p in str(sc.getConf().get(u'spark.submit.pyFiles')).split(','):
        if p not in sys.path:
            sys.path.append(p)
