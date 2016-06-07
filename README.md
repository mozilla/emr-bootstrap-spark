emr-bootstrap-spark
===================

This packages contains the AWS bootstrap scripts for Mozilla's flavoured Spark setup.

## Interactive job
```bash
export SPARK_PROFILE=telemetry-spark-cloudformation-TelemetrySparkInstanceProfile-1SATUBVEXG7E3
export SPARK_BUCKET=telemetry-spark-emr-2
export KEY_NAME=mozilla_vitillo
aws emr create-cluster \
  --region us-west-2 \
  --name SparkCluster \
  --instance-type c3.4xlarge \
  --instance-count 1 \
  --service-role EMR_DefaultRole \
  --ec2-attributes KeyName=${KEY_NAME},InstanceProfile=${SPARK_PROFILE} \
  --release-label emr-4.3.0 \
  --applications Name=Spark Name=Hive \
  --bootstrap-actions Path=s3://${SPARK_BUCKET}/bootstrap/telemetry.sh \
  --configurations https://s3-us-west-2.amazonaws.com/${SPARK_BUCKET}/configuration/configuration.json 
```

## Batch job
```bash
# Also export the vars from the 'interactive' section above.
export DATA_BUCKET=telemetry-public-analysis-2 # Or use the private bucket.
export CODE_BUCKET=telemetry-analysis-code-2
aws emr create-cluster \
  --region us-west-2 \
  --name SparkCluster \
  --instance-type c3.4xlarge \
  --instance-count 1 \
  --service-role EMR_DefaultRole \
  --ec2-attributes KeyName=${KEY_NAME},InstanceProfile=${SPARK_PROFILE} \
  --release-label emr-4.3.0 \
  --applications Name=Spark Name=Hive \
  --bootstrap-actions Path=s3://${SPARK_BUCKET}/bootstrap/telemetry.sh \
  --configurations https://s3-us-west-2.amazonaws.com/${SPARK_BUCKET}/configuration/configuration.json 
  --auto-terminate \
  --steps Type=CUSTOM_JAR,Name=CustomJAR,ActionOnFailure=TERMINATE_JOB_FLOW,Jar=s3://us-west-2.elasticmapreduce/libs/script-runner/script-runner.jar,Args=\["s3://${SPARK_BUCKET}/batch.sh","--job-name","foo","--notebook","s3://${CODE_BUCKET}/jobs/foo/Telemetry Hello World.ipynb","--data-bucket","${DATA_BUCKET}"\]
```

## Deploy to AWS via ansible
```bash
ansible-playbook ansible/deploy.yml -e '@ansible/envs/dev.yml' -i ansible/inventory
```

The Spark Jupyter notebook configuration is hosted at `https://s3-us-west-2.amazonaws.com/telemetry-spark-emr-2/jupyter_notebook_config.py`. At the moment, this is only needed for the GitHub Gist export option in the Jupyter notebook. The credentials it contains are managed under the [Mozilla GitHub account](https://github.com/mozilla/) by :whd. This file **should not be made public**.
