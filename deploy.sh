#!/bin/bash

aws s3 cp batch.sh s3://telemetry-spark-emr/batch.sh
aws s3 cp telemetry.sh s3://telemetry-spark-emr/telemetry.sh
