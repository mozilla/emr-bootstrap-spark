emr-bootstrap-spark
===================

This package contains the AWS bootstrap scripts for Mozilla's flavoured Spark setup.
The deployed scripts in S3 are referenced by
[ATMO clusters](https://github.com/mozilla/telemetry-analysis-service) and
[Airflow jobs](https://github.com/mozilla/telemetry-airflow).

## Interactive job
```bash
export SPARK_PROFILE=telemetry-spark-cloudformation-TelemetrySparkInstanceProfile-1SATUBVEXG7E3
export SPARK_BUCKET=telemetry-spark-emr-2
export KEY_NAME=20161025-dataops-dev
aws emr create-cluster \
  --region us-west-2 \
  --name SparkCluster \
  --instance-type c3.4xlarge \
  --instance-count 1 \
  --service-role EMR_DefaultRole \
  --ec2-attributes KeyName=${KEY_NAME},InstanceProfile=${SPARK_PROFILE} \
  --release-label emr-5.2.1 \
  --applications Name=Spark Name=Hive Name=Zeppelin \
  --bootstrap-actions Path=s3://${SPARK_BUCKET}/bootstrap/telemetry.sh \
  --configurations https://s3-us-west-2.amazonaws.com/${SPARK_BUCKET}/configuration/configuration.json \
  --steps Type=CUSTOM_JAR,Name=CustomJAR,ActionOnFailure=TERMINATE_JOB_FLOW,Jar=s3://us-west-2.elasticmapreduce/libs/script-runner/script-runner.jar,Args=\["s3://${SPARK_BUCKET}/steps/zeppelin/zeppelin.sh"\]
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
  --release-label emr-5.2.1 \
  --applications Name=Spark Name=Hive \
  --bootstrap-actions Path=s3://${SPARK_BUCKET}/bootstrap/telemetry.sh \
  --configurations https://s3-us-west-2.amazonaws.com/${SPARK_BUCKET}/configuration/configuration.json \
  --auto-terminate \
  --steps Type=CUSTOM_JAR,Name=CustomJAR,ActionOnFailure=TERMINATE_JOB_FLOW,Jar=s3://us-west-2.elasticmapreduce/libs/script-runner/script-runner.jar,Args=\["s3://${SPARK_BUCKET}/steps/batch.sh","--job-name","foo","--notebook","s3://${CODE_BUCKET}/jobs/foo/Telemetry Hello World.ipynb","--data-bucket","${DATA_BUCKET}"\]
```

## Deploy to AWS via ansible

To deploy to the staging location:

```bash
ansible-playbook ansible/deploy.yml -e '@ansible/envs/stage.yml' -i ansible/inventory
```

Once deployed, you can see the effects in action by launching a cluster via
[ATMO stage](https://atmo.stage.mozaws.net/).

To deploy for production clusters:

```bash
ansible-playbook ansible/deploy.yml -e '@ansible/envs/production.yml' -i ansible/inventory
```

The Spark Jupyter notebook configuration is hosted at `https://s3-us-west-2.amazonaws.com/telemetry-spark-emr-2/credentials/jupyter_notebook_config.py`. At the moment, this is only needed for the GitHub Gist export option in the Jupyter notebook. The credentials it contains are managed under the [Mozilla GitHub account](https://github.com/mozilla/) by :whd. This file **should not be made public**.


## Contributing to `emr-bootstrap-spark`

You may set up a development environment to test and verify modifications applied to this repository.

### Install prerequisite packages
```
pip install ansible boto boto3
```

### Create and bootstrap the development environment
* Define a new ansible environment in `env/dev-<username>.yml`
    * Set `spark_emr_bucket` to a unique bucket e.g. `telemetry-spark-emr-2-dev-<username>`
    * Set `stack_name` to a unique name e.g. `telemetry-spark-cloudformation-dev-<username>`
* Recursively copy assets from `staging` to `dev`
    * `aws s3 cp --recursive s3://telemetry-spark-emr-2-stage s3://telemetry-spark-emr-2-dev-<username>`
* Deploy to AWS using `ansible-playbook` on the new environment
* Launch a new instance using the appropriate `SPARK_PROFILE` and `SPARK_BUCKET` keys
    * Set `SPARK_PROFILE` to the cloudformation instance profile
        * This can be found as an output on the cloudformation dashboard
        * Alternatively:
            ```
               aws cloudformation describe-stacks --stack-name telemetry-spark-cloudformation-dev-<username> |
               jq '.Stacks[0].Outputs[0].OutputValue'
            ```
    * Set `SPARK_BUCKET` to `spark_emr_bucket` value in `env/dev-<username>.yml`
