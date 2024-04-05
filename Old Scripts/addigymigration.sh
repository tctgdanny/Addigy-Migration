#!/bin/bash

########################################################################################
################################## SCRIPT CONDITIONS ###################################
########################################################################################

migration_log="/var/tmp/migration_log.log"
if [[ ! -e "$migration_log" ]]; then
  touch "$migration_log"
fi

function sendToLog(){
### Sends a given string to the main migration log ###
    timeStamp=$(date "+%m/%d/%Y %H:%M:%S")
    /bin/echo "${timeStamp} $1" >> "$migration_log"
}

# Check if Swift Dialog is already running. If it is, kill.
if pgrep -xq -- "Dialog"; then
    killall Dialog
    exit 0
fi

sendToLog "Starting migration attempt: $(date)"
# Check for presence of SwiftDialog.
if [[ -e "/usr/local/bin/dialog" ]]; then
    sendToLog "Swift Dialog is already installed."
    swiftDialogVersion=$(defaults read "/Library/Application Support/Dialog/Dialog.app/Contents/Info.plist" CFBundleShortVersionString)
    if [[ "$swiftDialogVersion" == "2.4.2" ]]; then
        sendToLog "Swift Dialog version is up to date."
    else
        sendToLog "Swift Dialog version is out of date - installing 2.4.2"
        /usr/sbin/installer -pkg "/Library/Addigy/ansible/packages/Addigy Migration (2.1)/dialog-2.4.2-4755.pkg" -target /
    fi
else
    sendToLog "Swift Dialog not found - installing"
    /usr/sbin/installer -pkg "/Library/Addigy/ansible/packages/Addigy Migration (2.1)/dialog-2.4.2-4755.pkg" -target /
fi

# Check for presence of migration variables file.
if [[ ! -f "/Library/Addigy/Migration/.migration_variables.sh" ]]; then
  sendToLog "Variables file does not exist. Exiting script."
  exit 1
fi

########################################################################################
############################ PROMPT USER TO START MIGRATION ############################
########################################################################################

# Set deferral counter
deferralCounterFile="/Library/Addigy/defer_remaining_2.txt"
if [[ ! -f "$deferralCounterFile" ]]; then
  # Create starting deferral counter of 5.
  sudo touch "$deferralCounterFile"
  sudo echo "5" > "$deferralCounterFile"
fi

sendToLog "Sending initial confirmation prompt"
currentDeferralCount=$(sudo cat "$deferralCounterFile")
logoPath="/Library/Addigy/ansible/packages/Addigy Migration (2.1)/CoreLogoTransparent.png"
set +e
if [[ "$currentDeferralCount" -gt 0 ]]; then
  # Deferrals remain - include deferral button
  echo "${currentDeferralCount} deferrals remaining"
  while [ -z "$dialogResults" ]; do
    /usr/local/bin/dialog \
    --title "Addigy Migration Assistant" \
    --message "The Core needs to run a mandatory software migration on your computer. \n \nThis process should take 3-5 minutes. When you are ready, choose an option below. Please stay at your computer for the duration of the migration. \n \nFor support, contact The Core: 469-251-2673 | support@thecoretg.com" \
    --alignment center \
    --icon none \
    --ontop \
    --image "$logoPath" \
    --button1text "Ready!" \
    --button2text "Defer (${currentDeferralCount} Remaining)" \
    --position "center"
    dialogResults=$?
    done
else
  # No deferrals remain - do not include deferral button
  echo "${currentDeferralCount} deferrals remaining"
  while [ -z "$dialogResults" ]; do
    /usr/local/bin/dialog \
    --title "Addigy Migration Assistant" \
    --message "The Core needs to run a mandatory software migration on your computer. \n \nWhen you are ready, choose an option below. Please stay at your computer for the duration of the migration. \n \nFor support, contact The Core: 469-251-2673 | support@thecoretg.com" \
    --alignment center \
    --icon none \
    --ontop \
    --image "$logoPath" \
    --button1text "Ready!" \
    --position "center"
    dialogResults=$?
    done
fi
set -e

# Interpret results from user prompts
if [ "$dialogResults" = 0 ]; then
    echo "User chose to proceed."
elif [ "$dialogResults" = 2 ]; then
    echo "User chose to defer. Exiting script."
    ((currentDeferralCount--))
    sudo echo "$currentDeferralCount" > "$deferralCounterFile"
    exit 0
else 
    echo "Output: $dialogResults"
    echo "User did not choose to proceed or defer - likely a nuke or timeout"
    exit 0
fi

########################################################################################
################################## CREATE MAIN SCRIPT ##################################
########################################################################################
cat << "EOF" > /tmp/agent_migrator.sh
#!/bin/bash

##############################################
############# ESTABLISH LOG FILE #############

migration_log="/var/tmp/migration_log.log"
if [[ -e "$migration_log" ]]; then
  rm "$migration_log"
  touch "$migration_log"
fi

function sendToLog(){
### Sends a given string to the main migration log ###
    timeStamp=$(date "+%m/%d/%Y %H:%M:%S")
    /bin/echo "${timeStamp} $1" >> "$migration_log"
}

##############################################
################## VARIABLES #################

# Source variables 
if [[ -f "/Library/Addigy/Migration/.migration_variables.sh" ]]; then
  sendToLog "Sourcing variables"
  source "/Library/Addigy/Migration/.migration_variables.sh"
else
  sendToLog "Variables file does not exist. Exiting script."
  exit 1
fi

MDMLink="$MDMLink"
csvPath="/Library/Addigy/ansible/packages/Addigy Migration (2.1)/abm_devices.csv" # Export device list from ABM for devices expected to migrate
logoPath="/Library/Addigy/ansible/packages/Addigy Migration (2.1)/CoreLogoTransparent.png" # Core logo

# WiFi Credentials for Reconnecting
ssid="$ssid"
psk="$psk"

# Enter the API Credentials for the KandjiAPI
subDomain="$subDomain.api.kandji.io"
apiToken="$apiToken"

##############################################
########### Customize SwiftDialog ############

# Main SwiftDialog window variables
sdMessageFontSize="16"
sdTitleFontSize="24"
sdTitle="none"
sdIcon="/Library/Addigy/ansible/packages/Addigy Migration (2.1)/CoreLogoTransparent.png"
sdMessage="Addigy migration in progress. Please stay near your computer."

# SwiftDialog Enroll instructions based on OS
installSonoma="This device requires additional approval. \n\n Please double-click the 'Addigy' profile, then click 'Enroll' inside the System Settings menu."
installVentura="This device requires additional approval. \n\n Please double-click the 'Addigy' profile, then click 'Enroll' inside the System Settings menu. \n\n If you do not see a profile, please click on the clock on the top right of your computer to see if you have an update in System Settings."
installMonterey="This device requires additional approval. \n\n Please click 'Install' inside the System Preferences menu. \n\n If you do not see a profile, please click on the clock on the top right of your computer to see if you have an update in System Preferences."

##############################################
############## Smaller Functions #############

function osBasedInstruction(){
### Gives user instructions on manually approving profiles from the System Settings/Preferences app ###
if [[ -n "$osBasedText" ]]; then
  $swiftDialog --small --title "Action Required" --message "$osBasedText" --icon none --messagefont "size=16" --titlefont "size=24" --position topleft --progress 100 --button1disabled --button1text none --ontop --moveable --commandfile "$popupCommandFile" & sleep .1
fi
}

function dynamicInstruction(){
### Gives user other migration-related instructions. ###
if [[ -n "$instructionText" ]]; then
  $swiftDialog --small --title "Action Required" --message "$instructionText" --icon none --messagefont "size=16" --titlefont "size=24" --position topleft --progress 100 --button1disabled --button1text none --ontop --moveable --commandfile "$popupCommandFile" & sleep .1
fi
}

function dialogCommand(){
### Streamlines sending commands to the primary SwiftDialog command file ###
    /bin/echo "$@"  >> "$sdCommandFile"
    sleep .1
}

function dialogCommandSecondary(){
### Streamlines sending commands to the secondary SwiftDialog command file ###
    /bin/echo "$@"  >> "$popupCommandFile"
    sleep .1
}

function adeCheckComplete(){
### SwiftDialog command which marks the checking of the ADE status as complete ###
    sendToLog "ADE Check complete."
    dialogCommand "listitem: title: Check ADE Status, progress: 100"
    dialogCommand "listitem: title: Check ADE Status, status: success"
}

function migrationCompleteCheck(){
### Checks if the user approved the profile from System Settings or System Preferences ###
    sendToLog "Waiting for MDM to be installed or for Counter to timeout at 600"
    approvedCounter=0
    isApproved=$(profiles status -type enrollment | grep -o "User Approved")
    while [ -z "$isApproved" ] && [ "$approvedCounter" -lt "600" ]; do
        ((approvedCounter++))
        sendToLog "Approved counter is at: ${approvedCounter}"
        isApproved=$(profiles status -type enrollment | grep -o "User Approved")
        sleep 1
    done
    if [[ ! -z "$isApproved" ]]; then
        sendToLog "User approved MDM profile."
        dialogCommand "progress: 80"
    elif [[ "$approvedCounter" -eq "600" ]]; then
        sendToLog "User did not approve in 10 minutes."
    fi
}

function openMobileConfig(){
### Opens the mobileconfig profile in non-ADE enrollments - dynamic for use with System Settings/Preferences depending on OS version ###
    dialogCommand "progresstext: Verifying Addigy configuration profile."
    sendToLog "Opening Addigy profile"
    userID=$(id -u $(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }'))
    launchctl asuser "$userID" open "/Library/Addigy/mdm-profile-addigy.mobileconfig"

    # Wait 3 seconds, then open the profile again for good measure.
    sleep 3
    sendToLog "Opening again for good measure."
    launchctl asuser "$userID" open "/Library/Addigy/mdm-profile-addigy.mobileconfig"

    sleep 3
    userID=$(id -u $(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }'))
    if [[ "${osVersion}" -ge "13" ]]; then
        sendToLog "OS 13 or greater - opening System Settings for profile install."
        launchctl asuser "$userID" open "x-apple.systempreferences:com.apple.preferences.configurationprofiles"
    else  
        sendToLog "OS 12 or lower - opening System Preferences for profile install."
        launchctl asuser "$userID" open "/System/Library/PreferencePanes/Profiles.prefPane"
    fi

    sleep 1
    dialogCommand "progresstext: Waiting for your approval."
    osBasedInstruction
    migrationCompleteCheck
    exitMigrationApp
}

function checkInstallADE() {
### Checks if the Mac is to be ADE enrolled, and if so, finishes the migration ###
sendToLog "Checking ADE status"
if [ -n "${csvPath}" ]; then
  serialNumber="$(system_profiler SPHardwareDataType | awk '/Serial Number/{print $4}')"
  dialogCommand "progresstext: Checking if device is to be ADE enrolled."
  sleep 2
    if [[ "$(cat "${csvPath}" | grep "$serialNumber")" != "" ]];then
        adeCheckComplete
        dialogCommand "progresstext: ADE Device Identified. Running profiles command."
        sleep 3
        launchctl asuser "$(id -u $(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }'))" sudo profiles renew -type enrollment
        if [[ "${osVersion}" -eq "13" ]]; then
            open "x-apple.systempreferences:com.apple.preferences.configurationprofiles"
            osBasedInstruction
        elif [[ "${osVersion}" -lt "13" ]]; then
            open "/System/Library/PreferencePanes/Profiles.prefPane"
            osBasedInstruction
        fi
        migrationCompleteCheck
        exitMigrationApp
    else
        dialogCommand "progresstext: Device Serial not found in list. Continuing with Manual Enrollment."
        sleep 2
        adeCheckComplete
    fi
else
    sendToLog "No ABM csv file provided, skipping ADE check."
    adeCheckComplete
fi
}

function killSettingsApp() {
### Closes System Settings or Preferences depending on OS version ###
sendToLog "Closing settings app"
if [[ "$osVersion" -ge "13" ]]; then
  sysPrefApp="System Settings"
else
  sysPrefApp="System Preferences"
fi

if [[ $(ps aux | grep -v grep | grep "$sysPrefApp" | awk '{print $2}') != '' ]]; then
  for proc in $(ps aux | grep -v grep | grep "$sysPrefApp" | awk '{print $2}'); do
    kill -9 "$proc"
  done
else
  sendToLog "No $sysPrefApp app to close."
fi
}

function endMigrationPrompt() {
### Dynamic end-migration prompt independent from main migrator ###
sendToLog "Sending user end migration prompt"
/usr/local/bin/dialog \
--title "Addigy Migration Assistant" \
--message "$1" \
--alignment center \
--icon none \
--image "$logoPath" \
--button1text "OK" \
--position "center" \
--ontop
}

function endMigrationPrompt_noExit() {
### Dynamic end-migration prompt independent from main migrator ###
sendToLog "Sending user end migration prompt"
/usr/local/bin/dialog \
--title "Addigy Migration Assistant" \
--message "$1" \
--alignment center \
--icon none \
--image "$logoPath" \
--button1disabled \
--button1text none \
--position "center" \
--ontop
}

function cleanupFiles(){
### Cleans up all files related to the migration ###
sendToLog "Cleaning up all migration-related files."
migratorPlist="/Library/LaunchDaemons/com.migrator.plist"
scriptFile="/tmp/agent_migrator.sh"
packageFolder="/Library/Addigy/ansible/packages/Addigy Migration (2.1)"

if [[ -e "$scriptFile" ]]; then
    sudo rm "$scriptFile" && sendToLog "Script file removed"
fi

if [[ -d "$packageFolder" ]]; then
    sudo rm -rf "$packageFolder" && sendToLog "Package folder removed"
fi

if [[ -e "$migratorPlist" ]]; then 
    sudo rm "$migratorPlist" && sendToLog "Migrator plist file removed"
fi

if  sudo launchctl list | grep -q "com.migrator"; then
    sendToLog "Unloading migrator launch daemon - end of log"
    sudo launchctl remove com.migrator && sendToLog "Launch daemon unloaded"
fi

}

function exitMigrationApp() {
### Depending on current status, closes the migration app and utilizes end migration messages or retries ###
set +e
killSettingsApp

if sudo profiles -P | grep $AddigyMDMProfileIdentifier >& /dev/null; then
  dialogCommand "listitem: title: Addigy Enrollment, progress: 100"
  dialogCommand "listitem: title: Addigy Enrollment, status: success"
  dialogCommand "progresstext: Migration complete...cleaning up."
  sleep 2
  dialogCommand "quit:"
  endMigrationPrompt "Your Addigy migration is complete - you are free to continue use of your computer. \n\nThank you for your patience!"
  addigyMigrationFolder="/Library/Addigy/Migration"
  sudo rm -rf "$addigyMigrationFolder"
  cleanupFiles
  exit 0
elif [[ "$attemptCount" -lt "$maxAttempts" ]]; then
  dialogCommand "quit:"
  endMigrationPrompt "Hmm...it looks like an error occured with your migration. Please click 'OK' to attempt it again."
  migrationSuccess=0
  migrationAttempt
else
  dialogCommand "quit:"
  endMigrationPrompt_noExit "Hmm...it looks like an error occured with your migration. \n\nPlease reach out to The Core at your earliest convenience: \n\n469-251-2673 | support@thecoretg.com"
  exit 1
fi

}

############################################################################################################################################
####################################################### MAIN FUNCTIONS #####################################################################
############################################################################################################################################

##############################################
############# START SWIFT DIALOG #############
function startSwiftDialog(){
# Primary SwiftDialog variables & files
swiftDialog="/usr/local/bin/dialog"
sdCommandFile=$(mktemp /var/tmp/primaryCommandFile.XXX)
popupCommandFile=$(mktemp /var/tmp/secondaryCommandFile.XXX)

# Initialize list of items to add to swiftDialog list.
sendToLog "Starting startSwiftDialog function"
progressList=("Downloading Addigy Profile" "Removing Kandji" "Check Network" "Check ADE Status" "Addigy Enrollment")
listTotal=${#progressList[@]}
listIndexes=$((listTotal - 1))

dialogListString=""
for listItem in "${progressList[@]}"; do
    if [[ -z "$dialogListString" ]]; then 
        dialogListString+="$listItem"
    else
        dialogListString+=", $listItem"
    fi
done

sendToLog "Initializing main SwiftDialog window"
$swiftDialog --small --title "$sdTitle" --messagefont "size=${sdMessageFontSize}" --titlefont "size=${sdTitleFontSize}" --message "$sdMessage" --messagealignment center --icon none --progress 100 --position topleft --button1disabled --button1text none --ontop --moveable --commandfile "$sdCommandFile" & sleep .1
dialogCommand "list: ${dialogListString}"

# Give em all loading circles
for index in $(seq 0 $listIndexes); do
    dialogCommand "listitem: index: ${index}, status: progress"
done

sendToLog "End of startSwiftDialog function"
}

##############################################
########## DOWNLOAD ADDIGY PROFILE ###########
function downloadAddigyProfile(){
sendToLog "Start of downloadAddigyProfile function"
AddigyMDMProfileIdentifier="com.github.addigy.mdm.mdm"
KandjiMDMProfileIdentifier="com.kandji.profile.mdmprofile"
majorVersion=$(sw_vers -productVersion | awk -F. '{print $2}')
minorVersion=$(sw_vers -productVersion | awk -F. '{print $3}')
osVersion=$(sw_vers -productVersion | awk -F. '{print $1}')

# Set instructions text based on osVersion value
if [[ "$osVersion" -eq "14" ]]; then
    sendToLog "macOS Sonoma detected."
    osBasedText="$installSonoma"
elif [[ "$osVersion" -eq "13" ]]; then
    sendToLog "macOS Ventura detected."
    osBasedText="$installVentura"
else
    sendToLog "macOS Monterey or earlier detected."
    osBasedText="$installMonterey"
fi

# Download Addigy MDM Profile
mdmProfilePath="/Library/Addigy/mdm-profile-addigy.mobileconfig"
if [[ -e "$mdmProfilePath" ]]; then
  rm "$mdmProfilePath"
fi

MDMInstallLink="$MDMLink"
if [[ -n "$MDMInstallLink" ]]; then
  sendToLog "MDM install link found from variables file."
else
  sendToLog "MDM install link not found - erroring out."
  exitMigrationApp
fi

dialogCommand "listitem: title: Downloading Addigy Profile, progress: 50"
dialogCommand "progresstext: Downloading Addigy MDM Profile."
/Library/Addigy/go-agent download "$MDMInstallLink" "$mdmProfilePath"
dialogCommand "listitem: title: Downloading Addigy Profile, progress: 100"
dialogCommand "listitem: title: Downloading Addigy Profile, status: success"
dialogCommand "progress: 10"
sendToLog "End of downloadAddigyProfile function"
}

##############################################
############### REMOVE KANDJI ################
function removeKandji(){
sendToLog "Start of removeKandji function"

# Agent Removal Workflow
dialogCommand "progresstext: Checking for Kandji Agent."
sleep 1
if [[ -e "/usr/local/bin/kandji" ]]; then
  sendToLog "Kandji Agent is present - starting removal workflow."
  dialogCommand "progresstext: Removing Kandji Agent."
  sudo /usr/local/bin/kandji uninstall
  sleep 5
  if [[ -e "/usr/local/bin/kandji" ]]; then
    sendToLog "Error removing Kandji agent - exiting script."
    exitMigrationApp
  else
    sendToLog "Successfully removed Kandji agent"
  fi
fi

# Update progress bar
dialogCommand "listitem: title: Removing Kandji, progress: 50"
dialogCommand "progress: 20"

# Profile Removal Workflow
dialogCommand "progresstext: Checking for Kandji MDM profiles."
sleep 1
if sudo profiles -P | grep $KandjiMDMProfileIdentifier >& /dev/null; then
  sendToLog "Kandji MDM Profile is present - starting removal workflow."

  # Get serial number, and then get Device ID via Kandji API.
  serialNumber=$(system_profiler SPHardwareDataType | awk '/Serial Number/{print $4}')
  kDeviceID=$(curl -s "https://${subDomain}/api/v1/devices?serial_number=${serialNumber}" --header "Authorization: Bearer ${apiToken}" | json_pp | awk '/device_id/ {print $NF}' | tr -d ',"')
  if [[ -n ${kDeviceID} ]]; then
    dialogCommand "progresstext: Removing Kandji MDM Profile."
    curl -s --globoff --request DELETE "https://${subDomain}/api/v1/devices/${kDeviceID}" --header "Authorization: Bearer ${apiToken}"
  fi

  IFS=$'\n'
  profileRemovalCount=0
  profilesList=($(sudo profiles -L | grep Identifier))
  while [[ "${#profilesList[*]}" != "0" ]]; do
    profilesList=($(sudo profiles -L | grep Identifier))
    ((profileRemovalCount++))
    sendToLog "Attempting to remove Kandji profile - ${profileRemovalCount} tries so far."
    sleep 1

  done
fi

# Update progress bar
dialogCommand "progress: 40"
sleep 2
dialogCommand "listitem: title: Removing Kandji, progress: 100"
dialogCommand "listitem: title: Removing Kandji, status: success"
dialogCommand "progresstext: Kandji Profile Removed."
sleep 1


killSettingsApp
sendToLog "End of downloadAddigyProfile function"
}

##############################################
########## MANUAL WI-FI RECONNECTION #########
function manualReconnectPrompt(){
  sendToLog "Prompting user to manually reconnect to Wi-Fi."
  dialogCommand "progresstext: Awaiting your input."
  instructionText="Your Mac is currently disconnected from Wi-Fi and cannot continue migrating.\n\n Please reconnect manually to proceed."
  dynamicInstruction
  while [[ -z "$currentSSID" ]]; do
    sendToLog "User has not reconnected to Wi-Fi manually."
    sleep 5
    currentSSID=$(networksetup -getairportnetwork "$adapter" | awk -F': ' '{print $2}')
  done
  dialogCommandSecondary "quit:"
}

##############################################
######## AUTOMATIC WI-FI RECONNECTION ########
function reconnectWifi(){
sendToLog "Start of reconnectWifi function"
dialogCommand "progresstext: Verifying network connection."
sleep 5

# Ping Google's DNS server - if successful, no need to go through Wi-Fi reconnection, because the computer may be on ethernet.
sendToLog "Pinging Google to check if internet needs to be remediated"
ping -c 4 8.8.8.8 > /dev/null 2>&1

# Check the exit status of the ping command
if [ $? -eq 0 ]; then
  sendToLog "Internet connection is UP."
else
  sendToLog "Internet connection is DOWN."
  adapter=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}')
  wifi_status=$(networksetup -getairportpower "$adapter" | awk '{print $4}')
  currentSSID=$(networksetup -getairportnetwork "$adapter" | awk -F': ' '{print $2}')

  # If the org has an SSID and PSK variable, run the Wi-Fi function.
  if [[ "$wifi_status" == "On" ]] && [[ -z "$currentSSID" ]]; then
    sendToLog "Wi-Fi is on, but is not connected to an SSID."
    if [ -n "${ssid}" ] && [ -n "${psk}" ]; then
      sendToLog "MDM Wi-Fi SSID and PSK found. Attempting to reconnect."
      networksetup -setairportnetwork "${adapter}" "${ssid}" "${psk}"
      networksetup -addpreferredwirelessnetworkatindex "${adapter}" "${ssid}" 0 WPA2

      # If connection attempt failed, try again up to 4 more times.
      currentSSID=$(networksetup -getairportnetwork "$adapter" | awk -F': ' '{print $2}')
      if [[ -z $currentSSID ]]; then
        dialogCommand "progresstext: Reconnecting to Wi-Fi network."
        wifiCount=0
        sleep 1
          while [[ -z $currentSSID ]] && [[ "$wifiCount" -lt 3 ]]; do
            adapter=$(networksetup -listallhardwareports | awk '/Wi-Fi/{getline; print $2}')
            networksetup -setairportnetwork "${adapter}" "${ssid}" "${psk}"
            networksetup -addpreferredwirelessnetworkatindex "${adapter}" "${ssid}" 0 WPA2
            currentSSID=$(networksetup -getairportnetwork "$adapter" | awk -F': ' '{print $2}')
            ((wifiCount++))
            sleep 1
            dialogCommand "progresstext: Reconnecting to WiFi network... Attempt ${wifiCount}."
          done

        # Prompt the user to reconnect if they still aren't connected.
        if [[ -z "$currentSSID" ]]; then
          manualReconnectPrompt    
        fi
      fi
    else
      sendToLog "No WiFi Credentials to add from org."
      if [[ "$wifi_status" == "On" ]] && [[ -z "$currentSSID" ]]; then
        currentSSID=$(networksetup -getairportnetwork "$adapter" | awk -F': ' '{print $2}')
        if [[ -z "$currentSSID" ]]; then
        manualReconnectPrompt
        fi
      fi
    fi
  fi
fi

# Update progress bar
dialogCommand "listitem: title: Check Network, progress: 100"
dialogCommand "listitem: title: Check Network, status: success"
dialogCommand "progress: 60"
sendToLog "End of reconnectWifi function"
}

##############################################
########## ADDIGY MDM INSTALLATION ###########
function addigyMDMInstall(){
sendToLog "Start of addigyMDMInstall function"
# Checks macOS version in order to install MDM the best way possible.
dialogCommand  "progresstext: Checking macOS version compatibility."
sendToLog "OS Version is ${osVersion}"
# If OS version is Catalina - no promotion needed.
if ((majorVersion <= 15 && osVersion == 10)); then
    dialogCommand "progresstext: Installing Addigy MDM Profile."
    checkInstallADE
    profiles -IF "$mdmProfilePath"
    dialogCommand "progresstext: This device is on ${osVersion}.${majorVersion}.${minorVersion}. Installing the Addigy MDM Profile, user approval is needed."
    open '/System/Applications/System Preferences.app' &>/dev/null &
    open "/System/Library/PreferencePanes/Profiles.prefPane"
    migrationCompleteCheck
    exitMigrationApp
fi

# All of the below for macOS Big Sur and up.
currentUser=$(ls -la /dev/console | cut -d' ' -f4)
sendToLog "$currentUser is the current user"

# Check if user is an admin. If they are, finish migration process.
if [[ $(dscl . -read /Groups/admin GroupMembership 2> /dev/null | grep "$currentUser") != "" ]]; then
    sendToLog "Logged in user is already an admin."
    userAlreadyAdmin=true
    checkInstallADE
    openMobileConfig
    exitMigrationApp
else
    sendToLog "User is a standard user, moving to promotion"
    userAlreadyAdmin=false
fi

############# USER PROMOTION  ################
# If the user was not an admin prior to migration: promote user, and create a flag file so post-migration cleanup and demote the user if this script didn't end up doing it.
if [[ "$userAlreadyAdmin" = false ]]; then 
sudo dscl . -merge /Groups/admin GroupMembership "$currentUser" && touch "/Users/${currentUser}/.tempPromoted"
sendToLog "[Promotion complete]"
sendToLog "Created flag file"

## Check for ADE and then Demote when MDM is done installing with ADE. This is two sections because it needs a place for the user to get demoted.
serialNumber=$(system_profiler SPHardwareDataType | awk '/Serial Number/{print $4}')
dialogCommand "progresstext: Checking if device is ADE enrolled."
sleep 3
if [[ $(cat "${csvPath}" | grep "$serialNumber") == *"$serialNumber"* ]];then
    adeCheckComplete
    dialogCommand "progresstext: ADE Device Identified. Running profiles command."
    sleep 3
    launchctl asuser "$(id -u $(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }'))" sudo profiles renew -type enrollment
    if [[ "${osVersion}" -eq "13" ]]; then
        open "x-apple.systempreferences:com.apple.preferences.configurationprofiles"
        osBasedInstruction
    elif [[ "${osVersion}" -lt "13" ]]; then
        open "/System/Library/PreferencePanes/Profiles.prefPane"
        osBasedInstruction
    fi
    migrationCompleteCheck

############# ADE USER DEMOTION  ################

    sudo dseditgroup -o edit -d "$currentUser" -t user admin && rm "/Users/${currentUser}/.tempPromoted"
    sendToLog "[Demotion complete]"
    exitMigrationApp
fi

### End of ADE Check, Install, and Demote

############ NON ADE USER DEMOTION  ##############

## Demote when MDM Install is done installing with ADE
openMobileConfig

### DEMOTE LOGGED IN USER ###
sudo dseditgroup -o edit -d "$currentUser" -t user admin
rm "/Users/${currentUser}/.tempPromoted"
sendToLog "[Demotion complete]"
exitMigrationApp
fi
}

###############################################################
######################## MAIN WORKFLOW ########################


function mainWorkFlow(){
# Initial timestamp of migration for logs 
dateTime=$(date)
sendToLog "#####################################################################"
sendToLog "###################### NEW MIGRATION ATTEMPT ########################"
sendToLog "Migration attempt began at time: ${dateTime}"

# Caffeinate this script
caffeinate -d -i -m -u & sendToLog "Caffeinating script"

# Wait for active user session
FINDER_PROCESS=$(pgrep -l "Finder")
until [ "$FINDER_PROCESS" != "" ]; do
  sendToLog "$(date "+%Y-%m-%d %H:%M:%S"): Finder process not found. User session not active."
  sleep 1
  FINDER_PROCESS=$(pgrep -l "Finder")
done

# Run main functions
startSwiftDialog
downloadAddigyProfile
removeKandji
reconnectWifi
addigyMDMInstall
}

function migrationAttempt(){
while [[ "$migrationSuccess" -eq 0 ]] && [[ "$attemptCount" -lt "$maxAttempts" ]]; do
  ((attemptCount++))
  sendToLog "Migration Attempt: ${attemptCount}"
  migrationSuccess=1 && sendToLog "Setting migration success to '1' to assume success until it isn't."
  mainWorkFlow
done
}

migrationSuccess=0
attemptCount=0
maxAttempts=2

migrationAttempt
EOF

cat << "EOF" > /Library/LaunchDaemons/com.migrator.plist
 <?xml version="1.0" encoding="UTF-8"?>
 <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
 <plist version="1.0">
 <dict>
   <key>Label</key>
   <string>com.migrator</string>
   <key>ProgramArguments</key>
   <array>
     <string>bash</string>
     <string>/tmp/agent_migrator.sh</string>
   </array>
   <key>RunAtLoad</key>
   <true/>
   <key>KeepAlive</key>
   <true/>
   <key>WorkingDirectory</key>
   <string>/tmp</string>
   <key>StandardOutPath</key>
   <string>/tmp/Addigy_Migrator/logs/migrator.log</string>
   <key>StandardErrorPath</key>
   <string>/tmp/Addigy_Migrator/logs/migrator.log</string>
 </dict>
 </plist>
EOF

sudo launchctl load /Library/LaunchDaemons/com.migrator.plist