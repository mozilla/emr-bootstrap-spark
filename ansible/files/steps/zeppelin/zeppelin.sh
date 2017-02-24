#!/bin/bash
set -x

# Configure Spark
chmod o+w /mnt /mnt1
source $HOME/.bashrc

echo "export PYSPARK_PYTHON=$PYSPARK_PYTHON" | sudo tee -a /etc/zeppelin/conf/zeppelin-env.sh
sudo aws s3 cp s3://{{telemetry_analysis_spark_emr_bucket}}/configuration/zeppelin/interpreter.json /etc/zeppelin/conf/interpreter.json
sudo chown zeppelin:zeppelin /etc/zeppelin/conf/interpreter.json

# Enable matplotlib support
echo 'export MPLBACKEND="agg"' | sudo tee -a /etc/zeppelin/conf/zeppelin-env.sh

# Preload Scala packages
repositories="https://oss.sonatype.org/content/repositories/snapshots"
packages="com.mozilla.telemetry:moztelemetry_2.11:1.0-SNAPSHOT,vitillo:spark-hyperloglog:1.1.1"

echo ":quit" | spark-shell --master local[1] --repositories $repositories --packages $packages
sudo ln -s $HOME/.ivy2 /var/lib/zeppelin/.ivy2
sudo chmod -R o+rw $HOME/.ivy2

echo "export SPARK_SUBMIT_OPTIONS=\"--repositories $repositories --packages $packages\"" |
    sudo tee -a /etc/zeppelin/conf/zeppelin-env.sh

# Restart Zeppelin
sudo stop zeppelin
sudo start zeppelin
