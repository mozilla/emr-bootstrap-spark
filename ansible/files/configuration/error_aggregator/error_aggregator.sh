#!/bin/bash

# Load env variables needed to run SPARK
source /home/hadoop/.bashrc

cd /home/hadoop/telemetry-streaming/
/usr/bin/sbt "run-main com.mozilla.telemetry.streaming.ErrorAggregator --kafkaBroker 172.31.44.132:6667 \
                                                                       --outputPath s3n://telemetry-parquet"
