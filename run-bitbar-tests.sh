#!/bin/bash
# Pre-requisite for macos: brew install jq
bitbar_Path="https://cloud.bitbar.com/api/me"
script_Path="scripts"
filedownload_Path="https://cloud.bitbar.com/cloud/api/v2/me/files"

# You can add other user-entered variables here
echo "Enter your BitBar API Key, followed by [ENTER]:"
read -r bb_api_key
echo "Enter name for test run, followed by [ENTER]:"
read -r testrunname
echo "Rename template test run file"

# Copy the template config file and zip up source code and bit bar run shell script
cp $script_Path/android/run-tests-android.sh run-tests.sh
cp $script_Path/android/android-configuration-tmp configuration-android-"$testrunname"
echo "Compress app source folder for upload ..."       
zip -r ../android-test-files-"$testrunname".zip run-tests.sh ../flutter-gherkin-flutter-driver
echo "Upload files to BitBar cloud"
response4=$(curl -X POST -u "$bb_api_key": $bitbar_Path/files -F "file=@android-test-files-$testrunname.zip")
response4=("${response4[*]}") # convert to array
body=${response4[*]} # get all elements
fileid=$(echo "$body" | jq '.id')
echo "Zipped File ID: $fileid"
echo "Add file id to configuration file"
sed -i .bak "s/TEST_FILE_ID/$fileid/" configuration-android-"$testrunname"
rm ./*.bak
echo "Add test run name to configuration file (Build run number)"
sed -i .bak "s/TEST_RUN_NAME/$testrunname/" configuration-android-"$testrunname"
rm ./*.bak
echo "Set build/test cycle running on BitBar, using configuration file ..."
curl -H 'Content-Type:application/json' -u "$bb_api_key": $bitbar_Path/runs --data-binary @configuration-android-"$testrunname"
read -r -t 10 -p "10 second wait to allow for session delay ..."
echo "Retrieve project test runs list and extract latest Test Run ID ..."
response=$(curl -u "$bb_api_key": $bitbar_Path/projects/207073277/runs)
response=("${response[*]}") # convert to array
body=${response[*]} # get all elements
runid=$(echo "$body" | jq '.data[0].id')
echo "Test Run ID: $runid"
x=0
while [ $x -le 1 ]; do
  read -r -t 20 -p "20 second wait before rechecking if test run has ended .."
  response2=$(curl -u "$bb_api_key": $bitbar_Path/projects/207073277/runs/"$runid")
  response2=("${response2[*]}") # convert to array
  body=${response2[*]} # get all elements
  runstatus=$(echo "$body" | jq '.state') 
  finishedDeviceCount=$(echo "$body" | jq '.finishedDeviceCount')
  if [ "$finishedDeviceCount" -eq 1 ]; then
    echo "Test run status: $runstatus"
    echo "Test run is now finished, downloading report files ..."
    x=$(( x + 1 ))
    read -r -t 60 -p "Wait for report files to generate"
  else
    echo "Test run status: $runstatus"
  fi
done
echo "Retreive device session ids for test run"
response3=$(curl -u "$bb_api_key": $bitbar_Path/projects/207073277/runs/"$runid"/device-sessions)
response3=("${response3[*]}") # convert to array
body=${response3[*]} # get all elements
devicesessionid1=$(echo "$body" | jq '.data[0].id')
echo "Device Session ID: $devicesessionid1"
echo "Retrieve device 1 session reports"
response7=$(curl -u "$bb_api_key": $bitbar_Path/projects/207073277/runs/"$runid"/device-sessions/"$devicesessionid1"/output-file-set/files)
echo "$runid/$devicesessionid1"
response7=("${response7[*]}") # convert to array
body=${response7[*]} # get all elements
echo "$body"
filetodownload1=$(echo "$body" | jq '.data[0].id')
filetodownload2=$(echo "$body" | jq '.data[1].id')
filetodownload3=$(echo "$body" | jq '.data[2].id')
filetodownload4=$(echo "$body" | jq '.data[3].id')
echo "$testrunname"
curl -L -u "$bb_api_key": $filedownload_Path/"$filetodownload1"/file --output console-"$testrunname".log
curl -L -u "$bb_api_key": $filedownload_Path/"$filetodownload2"/file --output performance-"$testrunname".json
curl -L -u "$bb_api_key": $filedownload_Path/"$filetodownload3"/file --output output-files-"$testrunname".zip
curl -L -u "$bb_api_key": $filedownload_Path/"$filetodownload4"/file --output device-"$testrunname".log
ls -la
if grep -Fq "FAILED (in 1 packages)" console-"$testrunname".log; then
  echo "Bitbar Test Run $testrunname has failed scenarios." 1>&2
  exit 1
elif test -f "console-$testrunname.log"; then
  echo "Bitbar Test Run $testrunname has failed to run." 1>&2
  exit 1
else
  echo "Build passed"
fi
