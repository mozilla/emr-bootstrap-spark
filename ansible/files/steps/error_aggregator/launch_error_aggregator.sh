#!/bin/bash

# Install supervisord from pip because the version packaged with yum
# is prehistoric.
pip install supervisor
# Download supervisord configuration file
sudo aws s3 cp s3://{{telemetry_analysis_spark_emr_bucket}}/configuration/supervisord/supervisord.conf
mkdir -p /home/hadoop/logs
# Download error_aggregator script
sudo aws s3 cp s3://{{telemetry_analysis_spark_emr_bucket}}/configuration/error_aggregator/error_aggregator.sh
git clone https://github.com/mozilla/telemetry-streaming.git /home/hadoop/telemetry-streaming
# Add repo update to the crontab
TEMP_CRON=/tmp/newcron
crontab -l > $TEMP_CRON
echo "*/5 * * * * git diff HEAD origin/master --exit-code --quiet && git merge origin/master && pkill -f error_aggregator" >> $TEMP_CRON
crontab $TEMP_CRON
rm $TEMP_CRON
# Run the process supervisord
cd /home/hadoop && supervisord -c supervisord.conf
