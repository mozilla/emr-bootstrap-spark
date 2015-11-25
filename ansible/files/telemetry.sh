TELEMETRY_CONF_BUCKET=s3://telemetry-spark-emr-2
MEMORY_OVERHEAD=7000  # Tuned for c3.4xlarge
EXECUTOR_MEMORY=15000M
DRIVER_MEMORY=$EXECUTOR_MEMORY

# Install packages
sudo yum -y install git jq htop tmux libffi-devel aws-cli postgresql-devel zsh snappy-devel readline-devel

# Install custom packages, e.g. emacs
mkdir packages
aws s3 cp --recursive $TELEMETRY_CONF_BUCKET/packages/ ./packages
sudo yum -y install packages/*

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
wget -nc https://3230d63b5fc54e62148e-c95ac804525aac4b6dba79b00b39d1d3.ssl.cf1.rackcdn.com/Anaconda2-2.4.0-Linux-x86_64.sh
bash Anaconda2-2.4.0-Linux-x86_64.sh -b
$ANACONDAPATH/bin/pip install python_moztelemetry python_mozaggregator montecarlino runipy py4j==0.8.2.1 pyliblzma==0.5.3 plotly==1.6.16 seaborn==0.6.0

# Force Python 2.7 (Python executable path seems to be hardcoded in Spark)
sudo rm /usr/bin/python /usr/bin/pip
sudo ln -s $ANACONDAPATH/bin/python /usr/bin/python
sudo ln -s $ANACONDAPATH/bin/pip /usr/bin/pip
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

# Setup R environment
wget -nc https://mran.revolutionanalytics.com/install/RRO-3.2.1-el6.x86_64.tar.gz
tar -xzf RRO-3.2.1-el6.x86_64.tar.gz
cd RRO-3.2.1; sudo ./install.sh; cd ..
$ANACONDAPATH/bin/pip install rpy2
mkdir -p $HOME/R_libs

# Configure environment variables
echo "" >> $HOME/.bashrc
echo "export R_LIBS=$HOME/R_libs" >> $HOME/.bashrc
echo "export LD_LIBRARY_PATH=/usr/lib64/RRO-3.2.1/R-3.2.1/lib64/R/lib/" >> $HOME/.bashrc
echo "export PYTHONPATH=/usr/lib/spark/python/" >> $HOME/.bashrc
echo "export SPARK_HOME=/usr/lib/spark" >> $HOME/.bashrc
echo "export PATH=$ANACONDAPATH/bin:\$PATH" >> $HOME/.bashrc
echo "export _JAVA_OPTIONS=\"-Djava.io.tmpdir=/mnt1/ -Xmx$DRIVER_MEMORY\"" >> $HOME/.bashrc
echo "export PYSPARK_SUBMIT_ARGS=\"--packages com.databricks:spark-csv_2.10:1.2.0 --master yarn --deploy-mode client --executor-memory $EXECUTOR_MEMORY --conf spark.yarn.executor.memoryOverhead=$MEMORY_OVERHEAD pyspark-shell\"" >> $HOME/.bashrc

source $HOME/.bashrc

# Setup IPython
ipython profile create
cat << EOF > $HOME/.ipython/profile_default/startup/00-pyspark-setup.py
import os
spark_home = os.environ.get('SPARK_HOME', None)
execfile(os.path.join(spark_home, 'python/pyspark/shell.py'))
EOF

# Setup plotly
mkdir -p $HOME/.plotly && aws s3 cp $TELEMETRY_CONF_BUCKET/plotly_credentials $HOME/.plotly/.credentials

# Setup dotfiles
$(git clone --recursive https://github.com/vitillo/dotfiles.git;
  cd dotfiles;
  make install-vim install-tmux install-emacs)

# Launch IPython
mkdir -p $HOME/analyses && cd $HOME/analyses
wget -nc https://raw.githubusercontent.com/vitillo/emr-bootstrap-spark/master/Telemetry%20Hello%20World.ipynb
ipython notebook --browser=false&
