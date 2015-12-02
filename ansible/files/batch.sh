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

LOG="logs/$JOB_NAME.$(date +%Y%m%d%H%M%S).log"
PLOG="../$LOG"
S3_BASE="s3://$DATA_BUCKET/$JOB_NAME"

mkdir -p $HOME/analyses && cd $HOME/analyses
mkdir -p logs
mkdir -p output

if [ -n "$JAR" ]; then
    # Run JAR
    aws s3 cp "$JAR" .
    cd output
    echo "Beginning job $JOB_NAME ..." >> "$PLOG"
    spark-submit --master yarn-client "../${JAR##*/}" $ARGS >> "$PLOG" 2>&1
    echo "Finished job $JOB_NAME" >> "$PLOG"
    echo "'$MAIN' exited with code $?" >> "$PLOG"
else
    # Run notebook
    aws s3 cp "$NOTEBOOK" .
    cd output
    echo "Beginning job $JOB_NAME ..." >> "$PLOG"
    runipy "../${NOTEBOOK##*/}" "${NOTEBOOK##*/}" --pylab >> "$PLOG" 2>&1
    echo "Finished job $JOB_NAME" >> "$PLOG"
    echo "'$MAIN' exited with code $?" >> "$PLOG"
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
