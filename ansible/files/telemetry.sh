# logging for any errors during bootstrapping
exec >> /var/log/bootstrap-script.log
exec 2>&1

# we won't use `set -e` because that means that AWS would terminate the instance and we wouldn't get logs for why it failed

TELEMETRY_CONF_BUCKET=s3://telemetry-spark-emr-2
MEMORY_OVERHEAD=7000  # Tuned for c3.4xlarge
EXECUTOR_MEMORY=15000M
DRIVER_MIN_HEAP=1000M
DRIVER_MEMORY=$EXECUTOR_MEMORY

# Enable EPEL
sudo yum-config-manager --enable epel

# Install packages
curl https://bintray.com/sbt/rpm/rpm | sudo tee /etc/yum.repos.d/bintray-sbt-rpm.repo
sudo yum -y install git jq htop tmux libffi-devel aws-cli postgresql-devel zsh snappy-devel readline-devel emacs nethogs w3m
sudo yum -y install --nogpgcheck sbt # bintray doesn't sign packages for some reason, this isn't ideal but is the only way to install sbt

# Download jars
aws s3 sync $TELEMETRY_CONF_BUCKET/jars $HOME/jars

# Check for master node
IS_MASTER=true
if [ -f /mnt/var/lib/info/instance.json ]
then
    IS_MASTER=$(jq .isMaster /mnt/var/lib/info/instance.json)
fi

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
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
            echo 1>&2 "unrecognized option: $1"
            ;;
        *)
            break;
            ;;
    esac
    shift
done

# Setup Python
export ANACONDAPATH=$HOME/anaconda2
wget --no-clobber --no-verbose https://3230d63b5fc54e62148e-c95ac804525aac4b6dba79b00b39d1d3.ssl.cf1.rackcdn.com/Anaconda2-2.5.0-Linux-x86_64.sh
bash Anaconda2-2.5.0-Linux-x86_64.sh -b
$ANACONDAPATH/bin/pip install python_moztelemetry python_mozaggregator montecarlino jupyter-notebook-gist runipy boto3 parquet2hive py4j==0.8.2.1 pyliblzma==0.5.3 plotly==1.6.16 seaborn==0.6.0
rm Anaconda2-2.5.0-Linux-x86_64.sh

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

# Setup R environment
wget -nc https://mran.revolutionanalytics.com/install/RRO-3.2.1-el6.x86_64.tar.gz
tar -xzf RRO-3.2.1-el6.x86_64.tar.gz
rm RRO-3.2.1-el6.x86_64.tar.gz
cd RRO-3.2.1; sudo ./install.sh; cd ..
$ANACONDAPATH/bin/pip install rpy2
mkdir -p $HOME/R_libs

# Configure environment variables
echo "" >> $HOME/.bashrc
echo "export R_LIBS=$HOME/R_libs" >> $HOME/.bashrc
echo "export LD_LIBRARY_PATH=/usr/lib64/RRO-3.2.1/R-3.2.1/lib64/R/lib/" >> $HOME/.bashrc
echo "export PYTHONPATH=/usr/lib/spark/python/" >> $HOME/.bashrc
echo "export SPARK_HOME=/usr/lib/spark" >> $HOME/.bashrc
echo "export PYSPARK_PYTHON=$ANACONDAPATH/bin/python" >> $HOME/.bashrc
echo "export PATH=$ANACONDAPATH/bin:\$PATH" >> $HOME/.bashrc
echo "export _JAVA_OPTIONS=\"-Djava.io.tmpdir=/mnt1/ -Xmx$DRIVER_MEMORY -Xms$DRIVER_MIN_HEAP\"" >> $HOME/.bashrc
echo "export PYSPARK_SUBMIT_ARGS=\"--packages com.databricks:spark-csv_2.10:1.2.0 --master yarn --deploy-mode client --executor-memory $EXECUTOR_MEMORY --conf spark.yarn.executor.memoryOverhead=$MEMORY_OVERHEAD pyspark-shell\"" >> $HOME/.bashrc

source $HOME/.bashrc

# Setup Jupyter notebook
aws s3 cp $TELEMETRY_CONF_BUCKET/bootstrap/jupyter_notebook_config.py ~/.jupyter/jupyter_notebook_config.py

# Setup IPython
ipython profile create
cat << EOF > $HOME/.ipython/profile_default/startup/00-pyspark-setup.py
import os
spark_home = os.environ.get('SPARK_HOME', None)
execfile(os.path.join(spark_home, 'python/pyspark/shell.py'))
EOF

# Setup plotly
mkdir -p $HOME/.plotly && aws s3 cp $TELEMETRY_CONF_BUCKET/plotly_credentials $HOME/.plotly/.credentials

# Load Parquet datasets after Hive metastore is up
HIVE_CONFIG_SCRIPT=$(cat <<EOF
while ! hive -e 'show tables' > /dev/null; do sleep 1; done
/home/hadoop/anaconda2/bin/parquet2hive s3://telemetry-parquet/longitudinal | bash
exit 0
EOF
)
echo "${HIVE_CONFIG_SCRIPT}" | tee /tmp/hive_config.sh
chmod u+x /tmp/hive_config.sh
bash /tmp/hive_config.sh &

# Launch IPython
mkdir -p $HOME/analyses && cd $HOME/analyses
wget -nc https://raw.githubusercontent.com/mozilla/emr-bootstrap-spark/master/examples/Telemetry%20Hello%20World.ipynb
wget -nc https://raw.githubusercontent.com/mozilla/emr-bootstrap-spark/master/examples/Longitudinal%20Dataset%20Tutorial.ipynb
ipython notebook --browser=false&
