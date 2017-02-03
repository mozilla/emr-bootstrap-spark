#!/bin/bash

# Configure Spark
chmod o+w /mnt /mnt1
source $HOME/.bashrc

echo "export PYSPARK_PYTHON=$PYSPARK_PYTHON" | sudo tee -a /etc/zeppelin/conf/zeppelin-env.sh
sudo aws s3 cp s3://{{telemetry_analysis_spark_emr_bucket}}/configuration/zeppelin/interpreter.json /etc/zeppelin/conf/interpreter.json
sudo chown zeppelin:zeppelin /etc/zeppelin/conf/interpreter.json

# Enable matplotlib support
conda install -y pyqt=5
sudo yum -y install libXdmcp xorg-x11-server-Xvfb

sudo pkill Xvfb
nohup Xvfb &

echo 'export DISPLAY=:0.0' | sudo tee -a /etc/zeppelin/conf/zeppelin-env.sh

# Restart Zeppelin
sudo stop zeppelin
sudo start zeppelin
