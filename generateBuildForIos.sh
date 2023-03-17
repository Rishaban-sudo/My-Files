# variables

XCODEWORKSPACE_PATH="${1}"

WORKSPACE_NAME="${2}"
SCHEME_NAME="${3}"

KEYCHAIN_NAME="iosApp.keychain"
KEYCHAIN_PASSWORD="Zoho@2023"
SYSTEM_NAME=$USER

P12_CERTIFICATE=${4}
P12_CERTIFICATE_PWD=${5}

PROVISIONING_PROFILE=${6}

SDK="iphoneos"
XCCONFIG_NAME="${SCHEME_NAME}Release.xcconfig"
 
getProvisioningProfileUUID() {
    UUID=$(/usr/libexec/PlistBuddy -c 'Print :UUID' /dev/stdin <<< $(security cms -D -i "$PROVISIONING_PROFILE"))
}

getProvisioningProfileType()
{
    PROVISIONED_DEVICES=$(/usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' /dev/stdin <<< $(security cms -D -i "$PROVISIONING_PROFILE"))
    GET_TASK_ALLOW=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:get-task-allow' /dev/stdin <<< $(security cms -D -i "$PROVISIONING_PROFILE"))
    PROVISIONS_ALLDEVICES=$(/usr/libexec/PlistBuddy -c 'Print :ProvisionsAllDevices' /dev/stdin <<< $(security cms -D -i "$PROVISIONING_PROFILE"))

    if [ "$GET_TASK_ALLOW" = "true" ]
    then
        echo "development"
    else
        if [ "$PROVISIONS_ALLDEVICES" = "true" ]
        then
            echo "enterprise"
        else
            if [ "$PROVISIONED_DEVICES" = "" ]
            then
                echo "app-store"
            else
                echo "ad-hoc"
            fi
        fi
    fi
}

getProvisioningProfileName()
{
    PROVISIONING_NAME=$(/usr/libexec/PlistBuddy -c 'Print :Name' /dev/stdin <<< $(security cms -D -i "$PROVISIONING_PROFILE"))
    echo "${PROVISIONING_NAME}"
}

getTeamID() {
    TEAM_ID=$(grep -a -A 2 ApplicationIdentifierPrefix "${PROVISIONING_PROFILE}" | grep string | sed -e 's/<string>//' -e 's/<\/string>//' -e 's/ //')
    echo "${TEAM_ID}"
}

getSigningCertificate() {
    SIGNING_CERTIFICATE=$(openssl pkcs12 -in ${P12_CERTIFICATE} -nodes -passin pass:"$P12_CERTIFICATE_PWD" | openssl x509 -noout -subject | awk -F'[=/]' '{print $6}' | awk -F'[:]' '{print $1}')
    echo "${SIGNING_CERTIFICATE}"
}

getBundleIdentifier() {
    BUNDLE_IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' /dev/stdin <<< $(security cms -D -i "${PROVISIONING_PROFILE}") | cut -d '.' -f2-)
    echo "${BUNDLE_IDENTIFIER}"
}


addP12CertificateToKeychain() {
    # Create iosApp keychain
    security create-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_NAME}"

    # Append iosApp keychain to user domain
    security list-keychains -d user -s "${KEYCHAIN_NAME}" $(security list-keychains -d user | sed s/\"//g)

    # Remove relock timeout
    security set-keychain-settings "${KEYCHAIN_NAME}"

    # Unlock keychain
    security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_NAME}"

    if [ $? -eq 0 ]
    then
        echo "Keychain Unlocked Sucessfully"
        echo $?
    else
        echo "Failed to unlock the keychain"
        echo $?
    fi

    # Add p12 certificate to keychain
    security import "${P12_CERTIFICATE}" -A -k "${KEYCHAIN_NAME}" -P "${P12_CERTIFICATE_PWD}" -T /usr/bin/codesign
}

addProvisioningProfileToXcode() {
    getProvisioningProfileUUID
    cp "${PROVISIONING_PROFILE}" "/Users/$SYSTEM_NAME/Library/MobileDevice/Provisioning Profiles/${UUID}.mobileprovision"
}

createXCconfig() {

    CONFIG_STRING="#include \"Pods/Target Support Files/Pods-""${SCHEME_NAME}""/Pods-""${SCHEME_NAME}"".release.xcconfig\""
    CONFIG_STRING="${CONFIG_STRING}"$'\n'
    CONFIG_STRING="${CONFIG_STRING}"$'\n'

    CONFIG_STRING="${CONFIG_STRING}""APP_NAME = ${SCHEME_NAME}"
    CONFIG_STRING="${CONFIG_STRING}"$'\n'

    CONFIG_STRING="${CONFIG_STRING}""CODE_SIGN_IDENTITY = $(getSigningCertificate)"
    CONFIG_STRING="${CONFIG_STRING}"$'\n'

    CONFIG_STRING="${CONFIG_STRING}""DEVELOPMENT_TEAM = $(getTeamID)"
    CONFIG_STRING="${CONFIG_STRING}"$'\n'

    CONFIG_STRING="${CONFIG_STRING}""PRODUCT_BUNDLE_IDENTIFIER = $(getBundleIdentifier)"
    CONFIG_STRING="${CONFIG_STRING}"$'\n'

    CONFIG_STRING="${CONFIG_STRING}""PROVISIONING_PROFILE = $(getProvisioningProfileName)"
    CONFIG_STRING="${CONFIG_STRING}"$'\n'

    CONFIG_STRING="${CONFIG_STRING}""PROVISIONING_PROFILE_SPECIFIER = $(getProvisioningProfileName)"
    CONFIG_STRING="${CONFIG_STRING}"$'\n'

    echo "${CONFIG_STRING}" > "${XCODEWORKSPACE_PATH}/${SCHEME_NAME}/Configurations/Release/${XCCONFIG_NAME}"
}

createExportOptionsPlist() {

    cd "${XCODEWORKSPACE_PATH}"

    /usr/libexec/PlistBuddy -c "Clear dict" "exportOptions.plist"

    /usr/libexec/PlistBuddy -c "Add :destination string export" "exportOptions.plist"
    /usr/libexec/PlistBuddy -c "Add :method string $(getProvisioningProfileType)" "exportOptions.plist"
    /usr/libexec/PlistBuddy -c "Add :teamID string $(getTeamID)" "exportOptions.plist"
    /usr/libexec/PlistBuddy -c "Add :signingStyle string manual" "exportOptions.plist"

    /usr/libexec/PlistBuddy -c "Add :signingCertificate string $(getSigningCertificate)" "exportOptions.plist"

    /usr/libexec/PlistBuddy -c "Add :provisioningProfiles dict" "exportOptions.plist"
    getBundleIdentifier

    /usr/libexec/PlistBuddy -c "Add :provisioningProfiles:${BUNDLE_IDENTIFIER} string $(getProvisioningProfileName)" "exportOptions.plist"
}

archiveAndCreateIPA() {

    cd "${XCODEWORKSPACE_PATH}"


    if [ $? -eq 0 ]
    then
        echo "Command Executed Sucessfully"
        echo $?
    else
        echo "Command Failed"
        echo $?
    fi

    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "${KEYCHAIN_PASSWORD}" "/Users/$SYSTEM_NAME/Library/Keychains/$KEYCHAIN_NAME" &> /dev/null

    xcodebuild archive -workspace "${WORKSPACE_NAME}.xcworkspace" -scheme "${SCHEME_NAME}" -configuration "Release" clean archive -archivePath "Archive/${SCHEME_NAME}.xcarchive" -sdk "${SDK}"

    xcodebuild -exportArchive -exportOptionsPlist "exportOptions.plist" -archivePath "Archive/${SCHEME_NAME}.xcarchive" -exportPath 'Release'

}

removeProvisioningProfileFromXcode() {
    rm -rf "/Users/$SYSTEM_NAME/Library/MobileDevice/Provisioning Profiles/${UUID}.mobileprovision"
}

deleteKeychain() {
    # Delete temporary keychain
    security delete-keychain "${KEYCHAIN_NAME}"

    # default again user login keychain
    security list-keychains -d user -s login.keychain
}


# Execution
addP12CertificateToKeychain
addProvisioningProfileToXcode
createXCconfig
createExportOptionsPlist
archiveAndCreateIPA

# Clean Up
# removeProvisioningProfileFromXcode
deleteKeychain
