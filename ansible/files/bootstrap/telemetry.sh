#!/bin/bash

# logging for any errors during bootstrapping
exec > >(tee -i /var/log/bootstrap-script.log)
exec 2>&1

# we won't use `set -e` because that means that AWS would terminate the instance and we wouldn't get logs for why it failed

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
        --email)
            shift
            EMAIL=$1
            ;;
        --efs-dns)
            shift
            EFS_DNS=$1
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


CURRENT_KEY=`cat $HOME/.ssh/authorized_keys`
TELEMETRY_CONF_BUCKET=s3://{{telemetry_analysis_spark_emr_bucket}}
MEMORY_OVERHEAD=7000  # Tuned for c3.4xlarge
EXECUTOR_MEMORY=15000M
DRIVER_MIN_HEAP=1000M
DRIVER_MEMORY=$EXECUTOR_MEMORY
SETUP_HOME_DIR=false

#EFS Mounting - only on master
if [ -n "$EMAIL" ] && [ -n "$EFS_DNS" ] && "$IS_MASTER" ; then
    # Mount entire efs locally to check for user's dir
    mkdir -p /mnt/efs
    sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 "$EFS_DNS:/" /mnt/efs

    if [ ! -d "/mnt/efs/$EMAIL" ]; then
        # If no dir for this user, create it
        SETUP_HOME_DIR=true
        sudo mkdir -p "/mnt/efs/$EMAIL"
    fi

    sudo mkdir -p "/mnt/efs/$EMAIL/analyses"
    sudo mkdir -p "/mnt/efs/$EMAIL/.ssh"

    AUTH_KEYS_FILE="/mnt/efs/$EMAIL/.ssh/authorized_keys"
    sudo test -e "$AUTH_KEYS_FILE" || sudo touch "$AUTH_KEYS_FILE"

    # mount user's EFS dir on $HOME
    sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 "$EFS_DNS:/$EMAIL" "$HOME"

    # Set ownership of user dir
    sudo chown --recursive hadoop:hadoop "$HOME"

    # allow Jupyter to access analyses dir
    sudo chmod --recursive a+rw "$HOME/analyses"

    # fixes ssh access
    sudo chmod go-w "$HOME"
    sudo chmod 700 "$HOME/.ssh"
    sudo chmod 700 "$HOME/.ssh/authorized_keys"

elif "$IS_MASTER" ; then
    # if non-efs, mount $HOME on /mnt
    cp -r -p /home/hadoop /mnt
    sudo mount --bind --verbose /mnt/hadoop /home/hadoop

    mkdir -p $HOME/analyses
    SETUP_HOME_DIR=true
fi

if [ "$SETUP_HOME_DIR" = true ] ; then
    # Only execute this when using EFS and this is a new user, or when not using EFS

    # Download examples to analyses dir
    wget -nc -P "$HOME/analyses" https://raw.githubusercontent.com/mozilla/mozilla-reports/master/tutorials/telemetry_hello_world.kp/orig_src/Telemetry%20Hello%20World.ipynb
    wget -nc -P "$HOME/analyses" https://raw.githubusercontent.com/mozilla/mozilla-reports/master/tutorials/longitudinal_dataset.kp/orig_src/Longitudinal%20Dataset%20Tutorial.ipynb
    wget -nc -P "$HOME/analyses" https://raw.githubusercontent.com/mozilla/mozilla-reports/master/examples/new_report.kp/orig_src/New%2BReport.ipynb

    aws s3 sync $TELEMETRY_CONF_BUCKET/sbt $HOME # this fixes bintray 404s
    aws s3 sync $TELEMETRY_CONF_BUCKET/jars $HOME/jars

    mkdir -p $HOME/R_libs

    # Setup plotly
    mkdir -p $HOME/.plotly && aws s3 cp $TELEMETRY_CONF_BUCKET/credentials/plotly $HOME/.plotly/.credentials

    # Setup Jupyter notebook
    aws s3 cp $TELEMETRY_CONF_BUCKET/credentials/jupyter_notebook_config.py ~/.jupyter/jupyter_notebook_config.py
fi

# Enable EPEL
mirror="https://s3-us-west-2.amazonaws.com/net-mozaws-prod-us-west-2-ops-rpmrepo-mirror"
sudo tee /etc/yum.repos.d/epel.repo <<EOF
[epel]
name=Extra Packages for Enterprise Linux 6 - \$basearch
baseurl=${mirror}/epel/6/\$basearch
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-6

[epel-debuginfo]
name=Extra Packages for Enterprise Linux 6 - $basearch - Debug
baseurl=${mirror}/epel/6/\$basearch/debug
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-6
gpgcheck=1
EOF
sudo yum clean all
sudo yum makecache

# Install packages
sudo yum -y install git jq htop tmux libffi-devel aws-cli postgresql-devel zsh snappy-devel readline-devel emacs nethogs w3m

# Install sbt
sbt_version=0.13.15
aws s3 cp $TELEMETRY_CONF_BUCKET/sbt-$sbt_version.rpm $HOME/sbt.rpm
sudo yum -y localinstall $HOME/sbt.rpm
rm $HOME/sbt.rpm

# Setup Python
export ANACONDA_PATH={{telemetry_analysis_anaconda_path}}

ANACONDA_SCRIPT=Anaconda2-4.2.0-Linux-x86_64.sh
wget --no-clobber --no-verbose -P /mnt http://repo.continuum.io/archive/$ANACONDA_SCRIPT
bash /mnt/$ANACONDA_SCRIPT -b -p $ANACONDA_PATH

PIP_REQUIREMENTS_FILE=/tmp/requirements.txt
aws s3 cp $TELEMETRY_CONF_BUCKET/bootstrap/python-requirements.txt $PIP_REQUIREMENTS_FILE
$ANACONDA_PATH/bin/pip install -r $PIP_REQUIREMENTS_FILE

rm /mnt/$ANACONDA_SCRIPT
rm $PIP_REQUIREMENTS_FILE

conda create -n zeppelin python=3.6 cairo pillow -y -q
source activate zeppelin
aws s3 cp $TELEMETRY_CONF_BUCKET/bootstrap/python3-requirements.txt $PIP_REQUIREMENTS_FILE
pip install -r $PIP_REQUIREMENTS_FILE
rm $PIP_REQUIREMENTS_FILE
source deactivate zeppelin

AUTH_KEYS_PATH="$HOME/.ssh/authorized_keys"

# Add public key if it's not currently there
if [ -n "$PUBLIC_KEY" ] && ! sudo grep -q "$PUBLIC_KEY" "$AUTH_KEYS_PATH" ; then
    echo $PUBLIC_KEY | sudo tee -a "$AUTH_KEYS_PATH"
fi

if [ -n "$CURRENT_KEY" ] && ! sudo grep -q "$CURRENT_KEY" "$AUTH_KEYS_PATH" ; then
    echo "$CURRENT_KEY" | sudo tee -a "$AUTH_KEYS_PATH"
fi

# Schedule shutdown at timeout
if [ ! -z $TIMEOUT ]; then
    sudo shutdown -h +$TIMEOUT&
fi

# Continue only if master node
if [ "$IS_MASTER" = false ]; then
    exit
fi

# Setup Spark logging
sudo mkdir -p /mnt/var/log/spark
sudo chmod a+rw /mnt/var/log/spark
touch /mnt/var/log/spark/spark.log

# Setup R environment
cd /mnt
wget -nc https://mran.microsoft.com/install/RRO-3.2.1-el6.x86_64.tar.gz
tar -xzf RRO-3.2.1-el6.x86_64.tar.gz
rm RRO-3.2.1-el6.x86_64.tar.gz
cd RRO-3.2.1; sudo ./install.sh; cd $HOME
$ANACONDA_PATH/bin/pip install rpy2

# Setup global bash file
# .sh files in /etc/profile.d/ run whenever a user logs in
GLOBAL_BASHRC=/etc/profile.d/atmo.sh
sudo touch "$GLOBAL_BASHRC"
sudo chown hadoop:hadoop "$GLOBAL_BASHRC"
sudo chmod 700 "$GLOBAL_BASHRC"

# Configure environment variables
sudo echo "" >> "$GLOBAL_BASHRC"
sudo echo "export R_LIBS=$HOME/R_libs" >> "$GLOBAL_BASHRC"
sudo echo "export LD_LIBRARY_PATH=/usr/lib64/RRO-3.2.1/R-3.2.1/lib64/R/lib/" >> "$GLOBAL_BASHRC"
sudo echo "export PYTHONPATH=/usr/lib/spark/python/" >> "$GLOBAL_BASHRC"
sudo echo "export SPARK_HOME=/usr/lib/spark" >> "$GLOBAL_BASHRC"
sudo echo "export PYSPARK_PYTHON=$ANACONDA_PATH/bin/python" >> "$GLOBAL_BASHRC"
sudo echo "export PYSPARK_DRIVER_PYTHON=jupyter" >> "$GLOBAL_BASHRC"
sudo echo "export PYSPARK_DRIVER_PYTHON_OPTS=console" >> "$GLOBAL_BASHRC"
sudo echo "export PATH=$ANACONDA_PATH/bin:\$PATH" >> "$GLOBAL_BASHRC"
sudo echo "export _JAVA_OPTIONS=\"-Djava.io.tmpdir=/mnt1/ -Xmx$DRIVER_MEMORY -Xms$DRIVER_MIN_HEAP\"" >> "$GLOBAL_BASHRC"
sudo echo "export PYSPARK_SUBMIT_ARGS=\"--packages com.databricks:spark-csv_2.10:1.2.0 --master yarn --deploy-mode client --executor-memory $EXECUTOR_MEMORY --conf spark.yarn.executor.memoryOverhead=$MEMORY_OVERHEAD pyspark-shell\"" >> "$GLOBAL_BASHRC"
sudo echo "export HIVE_SERVER={{metastore_dns}}" >> "$GLOBAL_BASHRC"

source "$GLOBAL_BASHRC"


# Configure Jupyter
jupyter nbextension enable --py widgetsnbextension --user

jupyter serverextension enable --py jupyter_notebook_gist --user
jupyter nbextension install --py jupyter_notebook_gist --user
jupyter nbextension enable --py jupyter_notebook_gist --user

jupyter serverextension enable --py jupyter_spark --user
jupyter nbextension install --py jupyter_spark --user
jupyter nbextension enable --py jupyter_spark --user

# Launch Jupyter Notebook
cd $HOME/analyses

cat << EOF > /tmp/run_jupyter.sh
#!/bin/bash

while ! ((yum list spark-python | grep 'spark-python.noarch') && [ -f /usr/bin/pyspark ]); do sleep 60; done

PYSPARK_DRIVER_PYTHON=jupyter PYSPARK_DRIVER_PYTHON_OPTS="notebook --no-browser" /usr/bin/pyspark
EOF
chmod +x /tmp/run_jupyter.sh
/tmp/run_jupyter.sh &
