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
--release-label emr-4.1.0 \
--applications Name=Spark \
--bootstrap-actions Path=s3://${SPARK_BUCKET}/bootstrap/telemetry.sh \
--configurations https://s3-us-west-2.amazonaws.com/${SPARK_BUCKET}/configuration/configuration.json 
```

## Batch job
```bash
# Also export the vars from the 'interactive' section above.
export PUBLIC_BUCKET=telemetry-public-analysis-2
export CODE_BUCKET=telemetry-analysis-code
aws emr create-cluster \
  --name SparkCluster \
  --ami-version 3.3.2 \
  --instance-type c3.4xlarge \
  --instance-count 5 \
  --service-role EMR_DefaultRole \
  --ec2-attributes KeyName=${KEY_NAME},InstanceProfile=$SPARK_PROFILE \
  --bootstrap-actions Path=s3://support.elasticmapreduce/spark/install-spark,Args=\["-v","1.2.1"\] Path=s3://elasticmapreduce/bootstrap-actions/configure-hadoop,Args=["-y","yarn.nodemanager.vmem-check-enabled=false","-y","yarn.nodemanager.pmem-check-enabled=false"] Path=s3://${SPARK_BUCKET}/telemetry.sh,Args=\["--timeout","100"\] \
  --auto-terminate \
  --steps Type=CUSTOM_JAR,Name=CustomJAR,ActionOnFailure=TERMINATE_JOB_FLOW,Jar=s3://us-west-2.elasticmapreduce/libs/script-runner/script-runner.jar,Args=\["s3://${SPARK_BUCKET}/batch.sh","--job-name","foo","--notebook","s3://${CODE_BUCKET}/jobs/foo/Telemetry Hello World.ipynb","--data-bucket","${PUBLIC_BUCKET}"\]
```

## Deploy to AWS via ansible
```bash
ansible-playbook ansible/deploy.yml -e '@ansible/envs/dev.yml' -i ansible/inventory
```
