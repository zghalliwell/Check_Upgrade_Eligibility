#!/bin/bash

################################################################################
# This script can be put in self service to allow end users to view when 
# they are elligible for an upgrade for any computer or mobile device
# assigned to them based off the Warranty Expiration Date in the Purchasing tab of Jamf Pro.
# It will find all computers and devices assigned to user who runs it from 
# Self Service and will display upgrade dates for each device. 
#
# Please enter your Jamf Pro address in the variable below:
#######################
jamfProURL="my.jamf.pro"
#######################
# NOTE: leave out the "https://"
# 
#################
# AUTHENTICATION
#################
#
# This script utilizes 256 bit encryption to protect the username and password 
# of the API account. You'll want to pass the encrypted username string as     
# parameter 4 and the encrypted password string as parameter 5 from Jamf Pro   
# and then enter your SALT and PASSPHRASE for each in the variables below to decrypt them.
#
###########################################
usernameSALT="INSERT_SALT_HERE"
usernamePASSPHRASE="INSERT_PASSPHRASE_HERE"
passwordSALT="INSERT_SALT_HERE"
passwordPASSPHRASE="INSERT_PASSPHRASE_HERE"
###########################################
#
# You can use my Mr Encryptor script located at the link below to encrypt
# your username and password and generate the salt and passphrase:
#
# https://github.com/zghalliwell/MrEncryptor
#     			   
# The API account will need read-only access to user, computer, and mobile    
# device inventory records										               
################################################################################

#Launch a Jamf Helper window to let the user know it's working
"/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper" -windowType utility -title "Device Upgrade Eligibility" -description "Please wait while we check your stuff..." -alignDescription center &

#Establish the function to decrypt the username and password of the API account
function DecryptString() {
	echo "${1}" | /usr/bin/openssl enc -aes256 -d -a -A -S "${2}" -k "${3}"
}

##############################
# Establish starting variables and arrays
##############################

#Format for Decryption: DecryptString "parameter for encryption string" "Salt" "Pasphrase"
apiUser=$(DecryptString "$4" "$usernameSALT" "$usernamePASSPHRASE")
apiPass=$(DecryptString "$5" "$passwordSALT" "$passwordPASSPHRASE")

#Get the serial number of the device they are running the script from
echo "Gathering local hardware information..."
serial=$(system_profiler SPHardwareDataType | awk '/Serial Number/{print $4}')
echo "Computer serial number is $serial; information will be gathered based on the user assigned to this device."

#Arrays
computerName=()
mobileDeviceName=()
computerModel=()
mobileDeviceModel=()
computerWarrantyExpiration=()
mobileDeviceWarrantyExpiration=()
computerIDs=()
mobileDeviceIDs=()
mobileDeviceRecordArray=()

#Variables
computerCount=
mobileDeviceCount=
computerData=
mobileDeviceData=
message=

##############################
# Prelminary info gathering
##############################

echo "Gathering preliminary information..."

#First grab the inventory record of their computer and store it all as a variable
computerRecord1=$(curl -su $apiUser:$apiPass https://$jamfProURL/JSSResource/computers/serialnumber/$serial -H "Accept: text/xml" -X GET)
echo "Inventory record for local device found"

#Parse out the username of the user assigned to the Device in Jamf Pro 
jamfUser=$(echo $computerRecord1 | xmllint --xpath '/computer/location/username/text()' -)
echo "User assigned to device: $jamfUser"

#Get the first name of the user to use later in the final message
userFirstName=$(echo $computerRecord1 | xmllint --xpath '/computer/location/real_name/text()' - | awk -F ' ' '{ print $1 }')

#############################
# Gather Mobile Device Information
#############################

echo "Gathering mobile device information..."

#First get all of the mobile device data that matches the user
mobileDeviceData=$(curl -su $apiUser:$apiPass -H "Accept: text/xml" https://$jamfProURL/JSSResource/mobiledevices/match/$jamfUser)

#Get a count of how many mobile devices the user has
mobileDeviceCount=$(echo "$mobileDeviceData" | xmllint --xpath '/mobile_devices/size/text()' -)
echo "User $jamfUser has $mobileDeviceCount device(s) assigned to them in Jamf Pro"

#Build an array with all of the IDs of their devices
mobileDeviceIDs+=( $(echo $mobileDeviceData | xmllint --format - | awk -F '[<>]' '/<id>/{print $3}') )

#Build a for loop to get the inventory record for each device and save each inventory record in an array
for i in "${mobileDeviceIDs[@]}"; do
	mobileDeviceRecordArray+=( "$(curl -su $apiUser:$apiPass https://$jamfProURL/JSSResource/mobiledevices/id/$i -H "Accept: text/xml" -X GET)" )
	done

#Now build a for loop that will populate subsequent arrays with pieces of each individual inventory record
for i in "${mobileDeviceRecordArray[@]}";do
	mobileDeviceName+=( $(echo "$i" | xmllint --xpath '/mobile_device/general/display_name/text()' -) )
	mobileDeviceModel+=( "$(echo "$i" | xmllint --xpath '/mobile_device/general/model/text()' -)" )
	mobileDeviceWarrantyExpirationUnformatted=$(echo "$i" | xmllint --xpath '/mobile_device/purchasing/warranty_expires/text()' - )
	if [[ -n $mobileDeviceWarrantyExpirationUnformatted ]]; then
		mobileDeviceWarrantyExpiration+=( $(date -jn -f %F $mobileDeviceWarrantyExpirationUnformatted +%m/%d/%Y) )
		else
			echo "ERROR: Warranty field not filled out on inventory record for device"
			mobileDeviceWarrantyExpiration+=( "[Date not available, please contact IT]" )
			fi
	done

#############################
# Gather Computer Information
#############################

echo "Gathering computer information..."

#First get all of the computer data that matches the user
computerData=$(curl -su $apiUser:$apiPass -H "Accept: text/xml" https://$jamfProURL/JSSResource/computers/match/$jamfUser)

#Get a count of how many computers the user has
computerCount=$(echo "$computerData" | xmllint --xpath '/computers/size/text()' -)
echo "User $jamfUser has $computerCount computer(s) assigned to them in Jamf Pro"

#Build an array with all of the IDs of their computers
computerIDs+=( $(echo $computerData | xmllint --format - | awk -F '[<>]' '/<id>/{print $3}') )

#Build a for loop to get the inventory record for each computer and save each inventory record in an array
for i in "${computerIDs[@]}"; do
	computerRecordArray+=( "$(curl -su $apiUser:$apiPass https://$jamfProURL/JSSResource/computers/id/$i -H "Accept: text/xml" -X GET)" )
	done
	
#Now build a for loop that will populate subsequent arrays with pieces of each individual inventory record
for i in "${computerRecordArray[@]}";do
	computerName+=( $(echo "$i" | xmllint --xpath '/computer/general/name/text()' -) )
	computerModel+=( "$(echo "$i" | xmllint --xpath '/computer/hardware/model/text()' -)" )
	computerWarrantyExpirationUnformatted=$(echo "$i" | xmllint --xpath '/computer/purchasing/warranty_expires/text()' - )
	if [[ -n $computerWarrantyExpirationUnformatted ]]; then
		computerWarrantyExpiration+=( $(date -jn -f %F $computerWarrantyExpirationUnformatted +%m/%d/%Y) )
		else 
			echo "ERROR: Warranty field not filled out on inventory record for computer"
			computerWarrantyExpiration+=( "[Date not available, please contact IT]" )
		fi
	done
	
###################################
# Build the message
###################################

#Start the message
message="Hi $userFirstName!
Here's what we've got for ya!
"

#Subtract 1 from the count of devices and computers to aim at the correct array container
(( mobileDeviceCount -- ))
(( computerCount -- ))

#Build the message for Mobile Devices
if [[ $mobileDeviceCount < 0 ]]; then
	echo "The user has no mobile devices, moving on to computers."
	message="$message
	MOBILE DEVICES
	There are no mobile devices currently assigned to you.
	-------------"
	else
	for i in $(seq 0 $mobileDeviceCount); do
	count=$(($i+1))
	message="$message
	MOBILE DEVICES
	Mobile Device $count
	Name: ${mobileDeviceName[$i]}
	Model: ${mobileDeviceModel[$i]}
	Elligible for upgrade on ${mobileDeviceWarrantyExpiration[$i]}
	-------------"
	done
	fi

#Append the message to include computer information
if [[ $computerCount < 0 ]]; then
	echo "The user has no computers, finishing message."
	message="$message
	COMPUTERS
	There are no computers currently assigned to you.
	-------------"
	else 
	for i in $(seq 0 $computerCount); do
	count=$(($i+1))
	message="$message
	COMPUTERS
	Computer $count
	Name: ${computerName[$i]}
	Model: ${computerModel[$i]}
	Elligible for upgrade on ${computerWarrantyExpiration[$i]}
	-------------"
	done
	fi
	
#Finish the message
message="$message

If you have any further questions, please contact IT."

#Kill the jamf helper window that's telling the user to wait
jamf killJAMFHelper

#Display the final message to the user
osascript -e 'display dialog "'"$message"'" buttons {"OK"} default button 1'