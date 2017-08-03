HOME=/home/hadoop
source $HOME/.bashrc

# Error message
error_msg ()
{
    echo 1>&2 "Error: $1"
}

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --job-name)
            shift
            JOB_NAME=$1
            ;;
        --notebook)
            shift
            NOTEBOOK=$1
            ;;
        --jar)
            shift
            JAR=$1
            ;;
        --spark-submit-args)
            shift
            ARGS=$1
            ;;
        --data-bucket)
            shift
            DATA_BUCKET=$1
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

if [ -z "$JOB_NAME" ] || ([ -z "$NOTEBOOK" ] && [ -z "$JAR" ]) || ([ -n "$NOTEBOOK" ] && [ -n "$JAR" ]) || [ -z "$DATA_BUCKET" ]; then
    exit -1
fi

# Wait for Parquet datasets to be loaded
while ps aux | grep hive_config.sh | grep -v grep > /dev/null; do sleep 1; done

LOG="logs/$JOB_NAME.$(date +%Y%m%d%H%M%S).log"
PLOG="../$LOG"
S3_BASE="s3://$DATA_BUCKET/$JOB_NAME"

mkdir -p $HOME/analyses && cd $HOME/analyses
mkdir -p logs
mkdir -p output

EXIT_CODE=0

if [ -n "$JAR" ]; then
    # Run JAR
    aws s3 cp "$JAR" .
    cd output
    echo "Beginning job $JOB_NAME ..." >> "$PLOG"
    spark-submit --master yarn-client "../${JAR##*/}" $ARGS >> "$PLOG" 2>&1
    EXIT_CODE=$?
    echo "Finished job $JOB_NAME" >> "$PLOG"
    echo "'$MAIN' exited with code $EXIT_CODE" >> "$PLOG"
else
    # Run notebook
    aws s3 cp "$NOTEBOOK" .
    cd output
    echo "Beginning job $JOB_NAME ..." >> "$PLOG"

    NOTEBOOK_NAME=${NOTEBOOK##*/}
    EXTENSION=${NOTEBOOK_NAME##*.}
    FILE_NAME=${NOTEBOOK_NAME%.*}
    if [ $EXTENSION = "ipynb" ]; then
        # Executes Jupyter notebook
        PYSPARK_DRIVER_PYTHON=jupyter \
        PYSPARK_DRIVER_PYTHON_OPTS="nbconvert --ExecutePreprocessor.timeout=-1 --ExecutePreprocessor.kernel_name=python2 --to notebook --log-level=10 --execute \"../${NOTEBOOK_NAME}\" --allow-errors --output-dir ./ " \
        pyspark
        EXIT_CODE=$?
        if [ $EXIT_CODE != 0 ] || [ "`grep  '\"output_type\": \"error\"' \"$NOTEBOOK_NAME\"`" ] ;then
            PYSPARK_DRIVER_PYTHON=jupyter PYSPARK_DRIVER_PYTHON_OPTS="nbconvert --to markdown --stdout \"${NOTEBOOK_NAME}\"" pyspark
            EXIT_CODE=1
        fi
    fi
    if [ $EXTENSION = "json" ]; then
        # Executes Zeppelin notebook
        source activate zeppelin
        zeppelin-execute -i ../${NOTEBOOK_NAME} -o ./${NOTEBOOK_NAME}
        EXIT_CODE=$?
        zeppelin-convert -i ./${NOTEBOOK_NAME} -o ./${FILE_NAME}.md
        if [ $EXIT_CODE != 0 ]; then
            cat ${FILE_NAME}.md
            EXIT_CODE=1
        fi
        source deactivate zeppelin
    fi

    echo "Finished job $JOB_NAME" >> "$PLOG"
    echo "'$MAIN' exited with code $EXIT_CODE" >> "$PLOG"
fi

# Upload output files
find . -iname "*" -type f | while read f
do
    # Remove the leading "./"
    f=$(sed -e "s/^\.\///" <<< $f)
    echo $f

    UPLOAD_CMD="aws s3 cp './$f' '$S3_BASE/data/$f'"

    if [[ "$f" == *.gz ]]; then
        echo "adding 'Content-Type: gzip' for $f" >> "$PLOG"
        UPLOAD_CMD="$UPLOAD_CMD --content-encoding gzip"
    else
        echo "Not adding 'Content-Type' header for $f" >> "$PLOG"
    fi

    echo "Running: $UPLOAD_CMD" >> "$PLOG"
    eval $UPLOAD_CMD &>> "$PLOG"
done

# Upload log
cd ..
gzip "$LOG"
aws s3 cp "${LOG}.gz" "$S3_BASE/logs/$(basename "$LOG").gz" --content-type "text/plain" --content-encoding gzip
exit $EXIT_CODE
