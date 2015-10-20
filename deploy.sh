#!/bin/bash

aws s3 mb s3://telemetry-spark-emr-2

aws s3 cp batch.sh s3://telemetry-spark-emr-2/batch.sh
aws s3 cp telemetry.sh s3://telemetry-spark-emr-2/telemetry.sh
