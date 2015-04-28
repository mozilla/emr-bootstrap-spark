emr-bootstrap-spark
===================

This packages contains the AWS bootstrap scripts for Mozilla's flavoured Spark setup.

## Launch an interactive job
aws emr create-cluster --name SparkCluster --ami-version 3.3.2 --instance-type c3.4xlarge --instance-count 5 --service-role EMR_DefaultRole --ec2-attributes KeyName=mozilla_vitillo,InstanceProfile=telemetry-spark-emr --bootstrap-actions Path=s3://support.elasticmapreduce/spark/install-spark,Args=\["-v","1.2.1.a"\] Path=s3://telemetry-spark-emr/telemetry.sh

## Launch a batch job
aws emr create-cluster --name SparkCluster --ami-version 3.3.2 --instance-type c3.4xlarge --instance-count 5 --service-role EMR_DefaultRole --ec2-attributes KeyName=mozilla_vitillo,InstanceProfile=telemetry-spark-emr --bootstrap-actions Path=s3://support.elasticmapreduce/spark/install-spark,Args=\["-v","1.2.1"\] Path=s3://telemetry-spark-emr/telemetry.sh,Args=\["--timeout","100"\] --auto-terminate --steps Type=CUSTOM_JAR,Name=CustomJAR,ActionOnFailure=TERMINATE_JOB_FLOW,Jar=s3://us-west-2.elasticmapreduce/libs/script-runner/script-runner.jar,Args=\["s3://telemetry-spark-emr/batch.sh","--job-name","foo","--notebook","s3://telemetry-analysis-code/jobs/foo/Telemetry Hello World.ipynb","--data-bucket","telemetry-public-analysis"\]
