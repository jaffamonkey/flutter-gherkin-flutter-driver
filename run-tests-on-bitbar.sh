#!/bin/bash
# Pre-requisite for macos: brew install jq
# Pre-requisite for windows: https://sourceforge.net/projects/gnuwin32/files/
# Download: zip-3.0-bin.zip and bzip2-1.0.5-bin.zip
# Extract zip.exe and bzip2.dll from the `bin` folders inside zipfiles
# Copy both files to \Program Files\Git\usr\bin and restart GitBash terminal
# NOTE: If on Windows, erroneous CR's get added to files, which cause issues with those files on Mac and Linux platforms. So run the following
bitbar_Path="https://cloud.bitbar.com/api/me"
script_Path="shell-scripts"
testdriver_Path="test_driver"
filedownload_Path="https://cloud.bitbar.com/cloud/api/v2/me/files"

# GET USER INPUTS AND STORE AS VARIABLES
echo "Are you using Windows (win) or Mac (mac):"
read -r run_Platform
echo "Enter your project ID:"
read -r project_Id
echo "Enter your BitBar API Key:"
read -r BB_APIKEY
echo "Choose to run by the device group (g) or single device (s):"
read -r devices_Choice
echo "Enter device or device group id:"
read -r deviceid_GroupId
echo "Enter custom tag (e.g. @123456) or just tap [ENTER]:"
read -r custom_Tag
echo "Enter name for test run:"
read -r testrun_Name

# CHECK THAT DEVICE ID ENTERED EXISTS
response1=$(curl https://cloud.bitbar.com/api/v2/devices?limit=300)
response1=("${response1[*]}")> /dev/null # convert to array
body=${response1[*]} # get all elements
if [[ "$body" == *"$deviceid_GroupId"* ]]; then
  echo " Device id $deviceid_GroupId found"
else
  echo "Device id $deviceid_GroupId not found - please recheck your entry."
  exit 1
fi

# REMOVE FILES IF EXIST
echo "Remove files if exist"
FILE=run-tests.sh
if [[ -f "$FILE" ]]; then
  rm $FILE
fi
rm configuration*

# COPY RUN-TESTS.SH AND CONFIGURATION TEMPLATE
echo "Copy configuration and run-tests.sh files from templates"
cp $script_Path/android/run-tests-android.sh run-tests.sh
if [[ "$devices_Choice" = "g" ]]; then
  cp $script_Path/android/android-configuration-tmp-devicegroup configuration-android-"$testrun_Name"
elif [[ "$devices_Choice" = "s" ]]; then
  cp $script_Path/android/android-configuration-tmp-device configuration-android-"$testrun_Name"
else
  echo "Incorrect settings, please re-run"
fi

# ENSURE RUN-TESTS.SH FILE HAS NO ERONEOUS CARRRIAGE-RETURNS
echo "Remove any CR's (Carriage Returns) Windows might have added to run-tests.sh"
tr -d '\r' < run-tests.sh > run-tests2.sh
rm run-tests.sh
mv run-tests2.sh run-tests.sh

# CREATE CONFIGURATION FILES
echo "Rename template test run file ..."
if [[ "$devices_Choice" = "g" && "$run_Platform" == "mac" ]]; then
  sed -i .bak "s/DEVICE_GROUP_ID/$deviceid_GroupId/" configuration-android-"$testrun_Name"
  rm configuration-android-"$testrun_Name".bak
elif [[ "$devices_Choice" = "s" && "$run_Platform" == "mac" ]]; then
  sed -i .bak "s/DEVICE_ID/$deviceid_GroupId/" configuration-android-"$testrun_Name"
  rm configuration-android-"$testrun_Name".bak
elif [[ "$devices_Choice" = "g" && "$run_Platform" == "win" ]]; then
  sed -i "s/DEVICE_GROUP_ID/$deviceid_GroupId/" configuration-android-"$testrun_Name"
elif [[ "$devices_Choice" = "s" && "$run_Platform" == "win" ]]; then
  sed -i "s/DEVICE_ID/$deviceid_GroupId/" configuration-android-"$testrun_Name"
else
  echo "Incorrect settings, please re-run"
fi

# PREPARE ZIPFILE AND RETRIEVE FILE ID
echo "Compress app source folder for upload ..."       
zip -r android-test-files-"$testrun_Name".zip run-tests.sh analysis_options.yaml melos.yaml packages> /dev/null
echo "Upload files to BitBar cloud ..."
response2=$(curl -X POST -u "$BB_APIKEY": $bitbar_Path/files -F "file=@android-test-files-$testrun_Name.zip")
response2=("${response2[*]}")> /dev/null # convert to array
body=${response2[*]} # get all elements
fileid=$(echo "$body" | jq '.id')
echo "Zipped File ID: $fileid"

# ADD FILE ID AND TEST RUN NAME TO CONFIGURATION FILE
echo "Add file id, project id and test run name to configuration file"
if [ "$run_Platform" == "mac" ]; then
    sed -i .bak "s/TEST_FILE_ID/$fileid/" configuration-android-"$testrun_Name"
    sed -i .bak "s/TEST_RUN_NAME/$testrun_Name/" configuration-android-"$testrun_Name"
    sed -i .bak "s/PROJECT_ID/$project_Id/" configuration-android-"$testrun_Name"
    rm configuration-android-"$testrun_Name".bak
elif [ "$run_Platform" == "win" ]; then
    sed -i "s/TEST_FILE_ID/$fileid/" configuration-android-"$testrun_Name"
    sed -i "s/TEST_RUN_NAME/$testrun_Name/" configuration-android-"$testrun_Name"
    sed -i "s/PROJECT_ID/$project_Id/" configuration-android-"$testrun_Name"
else
  echo "Incorrect settings, please re-run"
fi

# ADD CUSTOM TAG IF SPECIFIED
if [[ "$custom_Tag" != "" && "$run_Platform" == "mac" ]]; then
    sed -i .bak "s/tagExpression = '@.*'/tagExpression = '$custom_Tag'/" $testdriver_Path/main_test.dart
    rm $testdriver_Path/main_test.dart.bak
elif [[ "$custom_Tag" != "" && "$run_Platform" == "win" ]]; then
    sed -i "s/tagExpression = '@.*'/tagExpression = '$custom_Tag'/" $testdriver_Path/main_test.dart
fi

# START TEST RUNNING ON BITBAR
echo "Set build/test cycle running on BitBar, using configuration file ..."
curl -H 'Content-Type:application/json' -u "$BB_APIKEY": $bitbar_Path/runs --data-binary @configuration-android-"$testrun_Name"> /dev/null

# RETRIEVE TEST RUN ID AND NUMBER OF DEVICE SESSIONS STARTED
read -r -t 10 -p "10 second wait to allow for session delay ..."
echo "Retrieve project test runs list and extract latest Test Run ID ..."
response3=$(curl -u "$BB_APIKEY": $bitbar_Path/projects/"$project_Id"/runs)
response3=("${response3[*]}")> /dev/null # convert to array
body=${response3[*]} # get all elements
runid=$(echo "$body" | jq '.data[0].id')
echo "Test Run ID: $runid"

# GET THE NUMBER OF DEVICES RUNNING FOR TEST RUN SESSION
response4=$(curl -u "$BB_APIKEY": $bitbar_Path/projects/"$project_Id"/runs/"$runid"/device-sessions)
response4=("${response4[*]}")> /dev/null  # convert to array
body=${response4[*]} # get all elements
numberdevicesessions=$(echo "$body" | jq '.data | length')
echo "The number of device sessions is: ""$numberdevicesessions"

# LOOP TO CHECK WHEN TEST RUN HAS FINISHED
x=0
while [ $x -ne 1 ]; do
  read -r -t 20 -p "Running ..."
  response5=$(curl -su "$BB_APIKEY": $bitbar_Path/projects/"$project_Id"/runs/"$runid")
  response5=("${response5[*]}")> /dev/null # convert to array
  body=${response5[*]} # get all elements
  runstatus=$(echo "$body" | jq '.state') 
  finishedDeviceCount=$(echo "$body" | jq '.finishedDeviceCount')
  if [ "$finishedDeviceCount" -eq  "$numberdevicesessions" ]; then
    echo "test run status: $runstatus"
    x=$(( x + 1 ))
    read -r -t 10 -p "Test run is now finished, downloading report files ..."
  else
    echo "test run status: $runstatus"
  fi
done

# LOOP THROUGH DEVICE SESSIONS AND DOWNLOAD REPORTS
echo "Cycle through device sessions and download reports for each"
count1=0
while [ $count1 -lt "$numberdevicesessions" ]; do
  response6=$(curl -u "$BB_APIKEY": $bitbar_Path/projects/"$project_Id"/runs/"$runid"/device-sessions)
  response6=("${response6[*]}")> /dev/null # convert to array
  body=${response6[*]} # get all elements
  devicesessionid=$(echo "$body" | jq '.data['"$count1"'].id')
  echo "Current device session id: ""$devicesessionid"
  echo "Retrieve device ""$count1"" session reports ..."
  response7=$(curl -u "$BB_APIKEY": $bitbar_Path/projects/"$project_Id"/runs/"$runid"/device-sessions/"$devicesessionid"/output-file-set/files)
  response7=("${response7[*]}")> /dev/null # convert to array
  body=${response7[*]} # get all elements
  filetodownload1=$(echo "$body" | jq '.data[0].id')
  filetodownload2=$(echo "$body" | jq '.data[1].id')
  filetodownload3=$(echo "$body" | jq '.data[2].id')
  filetodownload4=$(echo "$body" | jq '.data[3].id')
  filetodownload5=$(echo "$body" | jq '.data[4].id')
  curl -L -u "$BB_APIKEY": $filedownload_Path/"$filetodownload1"/file --output console-"$testrun_Name"-"$count1".log
  curl -L -u "$BB_APIKEY": $filedownload_Path/"$filetodownload2"/file --output performance-"$testrun_Name"-"$count1".json
  curl -L -u "$BB_APIKEY": $filedownload_Path/"$filetodownload3"/file --output output-files-"$testrun_Name"-"$count1".zip
  curl -L -u "$BB_APIKEY": $filedownload_Path/"$filetodownload4"/file --output video-"$testrun_Name"-"$count1".mp4
  curl -L -u "$BB_APIKEY": $filedownload_Path/"$filetodownload5"/file --output device-"$testrun_Name"-"$count1".log
  count1=$(( count1 + 1 ))
done

# RESET TAG
if [[ "$custom_Tag" != "" && "$run_Platform" == "mac" ]]; then
    sed -i .bak "s/tagExpression = '$custom_Tag'/tagExpression = '@smoke'/" $testdriver_Path/main_test.dart
    rm $testdriver_Path/main_test.dart.bak
elif [[ "$custom_Tag" != "" && "$run_Platform" == "win" ]]; then
    sed -i "s/tagExpression = '$custom_Tag'/'@smoke'/" $testdriver_Path/main_test.dart
fi

# CHECK FOR FAILURE THEN PASS/FAIL BUILD ACCORDINGLY
count2=0
while [ $count2 -lt "$numberdevicesessions" ]; do
  if grep -Fq "FAILED (in 1 packages)" console-"$testrun_Name"-$count2.log; then
    echo "Bitbar Device $count2 Test Run $testrun_Name has failed scenarios." 1>&2
    exit 1
  elif test -f "console-$testrun_Name-$count2.log"; then
    echo "Bitbar Device $count2 Test Run $testrun_Name has failed to run." 1>&2
    exit 1
  else
    echo " Device $count2 Test Run passed"
  fi
  count2=$(( count2 + 1 ))
done
