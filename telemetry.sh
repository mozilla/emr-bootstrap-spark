sudo yum -y install git jq htop tmux libffi-devel aws-cli postgresql-devel zsh

INSTANCES=$(jq .instanceCount /mnt/var/lib/info/job-flow.json)
FLOWID=$(jq -r .jobFlowId /mnt/var/lib/info/job-flow.json)
EXECUTORS=$(($INSTANCES>1?$INSTANCES:2 - 1))
EXECUTOR_CORES=$(nproc)
MAX_YARN_MEMORY=$(grep /home/hadoop/conf/yarn-site.xml -e "yarn\.scheduler\.maximum-allocation-mb" | sed 's/.*<value>\(.*\).*<\/value>.*/\1/g')
EXECUTOR_MEMORY=$(echo "($MAX_YARN_MEMORY - 1024 - 384) - ($MAX_YARN_MEMORY - 1024 - 384) * 0.07 " | bc | cut -d'.' -f1)M
DRIVER_MEMORY=$EXECUTOR_MEMORY
HOME=/home/hadoop

# Error message
error_msg ()
{
	echo 1>&2 "Error: $1"
}

# Check for master node
IS_MASTER=true
if [ -f /mnt/var/lib/info/instance.json ]
then
	IS_MASTER=$(jq .isMaster /mnt/var/lib/info/instance.json)
fi

# Parse arguments
while [ $# -gt 0 ]; do
	case "$1" in
		--num-executors)
			shift
			EXECUTORS=$1
			;;
		--executor-cores)
			shift
			EXECUTOR_CORES=$1
			;;
		--executor-memory)
			shift
			EXECUTOR_MEMORY=$1g
			;;
		--driver-memory)
			shift
			DRIVER_MEMORY=$1g
			;;
		--public-key)
			shift
			PUBLIC_KEY=$1
			;;
		--timeout)
			shift
			TIMEOUT=$1
			;;
		-*)
			# do not exit out, just note failure
			error_msg "unrecognized option: $1"
			;;
		*)
			break;
			;;
	esac
	shift
done

# Setup Spark
sudo chown hadoop:hadoop /mnt

# Setup Python
wget https://3230d63b5fc54e62148e-c95ac804525aac4b6dba79b00b39d1d3.ssl.cf1.rackcdn.com/Anaconda-2.2.0-Linux-x86_64.sh
bash Anaconda-2.2.0-Linux-x86_64.sh -b

$HOME/anaconda/bin/pip install python_moztelemetry montecarlino py4j==0.8.2.1 pyliblzma==0.5.3 plotly==1.6.16

# Force Python 2.7 (Python executable path seems to be hardcoded in Spark)
sudo rm /usr/bin/python /usr/bin/pip
sudo ln -s $HOME/anaconda/bin/python /usr/bin/python
sudo ln -s $HOME/anaconda/bin/pip /usr/bin/pip
sudo sed -i '1c\#!/usr/bin/python2.6' /usr/bin/yum

# Add public key
if [ -n "$PUBLIC_KEY" ]; then
	echo $PUBLIC_KEY >> $HOME/.ssh/authorized_keys
fi

# Schedule shutdown at timeout
if [ ! -z $TIMEOUT ]; then
	sudo shutdown -h +$TIMEOUT&
fi

# Continue only if master node
if [ "$IS_MASTER" = false ]; then
	exit
fi

# Configure environment variables
cat << EOF >> $HOME/.bashrc

# Spark configuration
export PYTHONPATH=$HOME/spark/python/
export SPARK_HOME=$HOME/spark
export _JAVA_OPTIONS="-Dlog4j.configuration=file:///home/hadoop/spark/conf/log4j.properties -Xmx$DRIVER_MEMORY"
export PATH=~/anaconda/bin:$PATH
EOF

# Here we are using striping on the assumption that we have a layout with 2 SSD disks!
SPARK_CONF=$(cat <<EOF
--conf spark.local.dir=/mnt,/mnt1 \
--conf spark.akka.frameSize=500 \
--conf spark.io.compression.codec=lzf \
--conf spark.serializer=org.apache.spark.serializer.KryoSerializer
EOF
)

if [ $EXECUTORS -eq 1 ]; then
	echo "export PYSPARK_SUBMIT_ARGS=\"--master local[*] $SPARK_CONF\"" >> $HOME/.bashrc
else
	echo "export PYSPARK_SUBMIT_ARGS=\"--master yarn --deploy-mode client --num-executors $EXECUTORS --executor-memory $EXECUTOR_MEMORY --executor-cores $EXECUTOR_CORES $SPARK_CONF\"" >> $HOME/.bashrc
fi

source $HOME/.bashrc

# Setup IPython
ipython profile create
cat << EOF > $HOME/.ipython/profile_default/startup/00-pyspark-setup.py
import os

spark_home = os.environ.get('SPARK_HOME', None)
execfile(os.path.join(spark_home, 'python/pyspark/shell.py'))
EOF

# Dump Spark logs to a file
cat << EOF > $SPARK_HOME/conf/log4j.properties
# Initialize root logger
log4j.rootLogger=INFO, FILE

# Set everything to be logged to the console
log4j.rootCategory=INFO, FILE

# Ignore messages below warning level from Jetty, because it's a bit verbose
log4j.logger.org.eclipse.jetty=WARN

# Set the appender named FILE to be a File appender
log4j.appender.FILE=org.apache.log4j.FileAppender

# Change the path to where you want the log file to reside
log4j.appender.FILE.File=$HOME/spark.log

# Prettify output a bit
log4j.appender.FILE.layout=org.apache.log4j.PatternLayout
log4j.appender.FILE.layout.ConversionPattern=%d{yy/MM/dd HH:mm:ss} %p %c{1}: %m%n
EOF

# Setup plotly
mkdir $HOME/.plotly && aws s3 cp s3://telemetry-spark-emr/plotly_credentials $HOME/.plotly/.credentials

# Install external packages, e.g. emacs
mkdir packages
aws s3 cp --recursive s3://telemetry-spark-emr/packages/ ./packages
sudo yum install packages/*

# Setup dotfiles
$(git clone --recursive https://github.com/vitillo/dotfiles.git;
  cd dotfiles;
  make install-vim install-tmux install-emacs;)

mkdir -p $HOME/analyses && cd $HOME/analyses
wget https://raw.githubusercontent.com/vitillo/emr-bootstrap-spark/master/Telemetry%20Hello%20World.ipynb
ipython notebook --browser=false&
