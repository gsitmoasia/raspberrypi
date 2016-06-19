#!/bin/bash

checkForErrorAndExit() {
    local errorMsg=$1
    local errorCode=$?
    if [ ${errorCode} -ne 0 ]
    then
        echo "ERROR - ${errorMsg}, error code is ${errorCode}. Exit with error."
        exit 1
    fi
}

trim() {
    #remove leading and tailing quotes and spaces
    local str=$1
    local trimmed=$(echo -e "${str}" | sed -e 's/^\"//' -e 's/\"$//')
    trimmed=$(echo -e "${trimmed}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    echo ${trimmed} 
}

speechToText() {
    local sttLanguage=$1
    local sttDuration=$2
    local sttHardware=$3
    local tmpFile="voice_control_stt"
    local tmpLogFile="/dev/shm/${tmpFile}.log"
    local tmpFlacFile="/dev/shm/${tmpFile}.flac"

    #clear out the log file
    rm ${tmpLogFile}
    checkForErrorAndExit "failed to rm ${tmpLogFile}"

    arecord -D ${sttHardware} -f S16_LE -d ${sttDuration} -r 16000 | flac - -f --best --sample-rate 16000 -o ${tmpFlacFile} >> ${tmpLogFile} 2>&1 
    checkForErrorAndExit "failed to record voice"

    local rawData=`curl -X POST --data-binary @${tmpFlacFile} --user-agent 'Mozilla/5.0' --header 'Content-Type: audio/x-flac; rate=16000;' "https://www.google.com/speech-api/v2/recognize?output=json&lang=${sttLanguage}&key=AIzaSyBOti4mM-6x9WDnZIjIeyEU21OpBXqWBgw&client=Mozilla/5.0" 2>> ${tmpLogFile}` 
    checkForErrorAndExit "failed to call google speech-to-text api"

    local results=`echo ${rawData} | sed -e 's/[{}]/''/g' | awk -F":" '{print $5}' | awk -F"," '{print $1}' | tr -d '\n'`
    checkForErrorAndExit "failed to parser search results"

    rm ${tmpFlacFile}
    checkForErrorAndExit "failed to remove ${tmpFlacFile}"

    echo ${results}
}

textToSpeech() {
    local ttsLanguage=$1
    local speechText=$2
    local tmpFile="/dev/shm/voice_control_tts"
    local tmpLogFile="${tmpFile}.log"
    local tmpSpeechFile="${tmpFile}.mp3"
    local tmpPartialFile="${tmpFile}_tmp.mp3"

    #clear out the log file
    rm ${tmpLogFile}
    checkForErrorAndExit "failed to rm ${tmpLogFile}"

    #clear out the output file
    echo "" > "${tmpSpeechFile}"
    checkForErrorAndExit "failed to create ${tmpSpeechFile}"
 
    #process one line at a time
    echo "${speechText}" | while IFS= read -r line
    do
        local remaining=""
        local processing="${line}"
        local len=0
        local lastWord=""
        while true
        do
            len=${#processing}
            if [ $len -le 0 ]
            then
                break
            elif [ $len -gt 100 ]
            then 
                #lets split this up so that its a maximum of 100 characters
                remaining=${processing:100}
                processing=${processing:0:100}
            
                #now we need to make sure there aren't split words, let's find the last space and the string after it
                lastWord=${processing##* }
        
                #here we are shortening the tmp string
                len=`expr 100 - ${#lastWord}` 
                processing=${processing:0:len}
            
                #now we concatenate and the string is reconstructed
                remaining="${lastWord}${remaining}"
            fi
    
            #get the first 100 characters
            wget -q -U Mozilla -O "${tmpPartialFile}" "http://translate.google.com/translate_tts?ie=UTF-8&total=1&idx=0&textlen=${len}&client=tw-ob&q=${processing}&tl=${ttsLanguage}"
            checkForErrorAndExit "failed to call google text-to-speech api"
    
            cat "${tmpPartialFile}" >> "${tmpSpeechFile}"
            checkForErrorAndExit "failed to append to ${tmpSpeechFile}"

            processing="${remaining}"
            remaining=""
        done
    done

    #now we finally say the whole thing
    cat "${tmpSpeechFile}" | mpg123 - >> ${tmpLogFile} 2>&1
    checkForErrorAndExit "failed to call mpg for ${tmpSpeechFile}"
}

callWolframAlpha() {
    local input=$1
    local tmpFile="/dev/shm/voice_control_ai"
    local tmpLogFile="${tmpFile}.log"

    #clear out the log file
    rm ${tmpLogFile}
    checkForErrorAndExit "failed to rm ${tmpLogFile}"

    local encodedInput=$( echo "${input}" | sed 's/ /%20/g' )
    local rawData=`curl -X POST "http://api.wolframalpha.com/v2/query?input=${encodedInput}&appid=VT6QX6-RT56ELQE3E&format=plaintext" 2>> ${tmpLogFile}`
    checkForErrorAndExit "failed to call wolframalpha api"
    
    echo "\n$input\n$rawData\n" >> test_data.txt

    local podCount=0
    local resultPattern="^pod title=.*"
    echo "${rawData}\n" | while read_dom
    do
        if [[ ${entity} =~ ${resultPattern} ]]
        then
            (( podCount += 1 ))
        elif [[ ${podCount} -ge 2 ]] && [[ "${entity}" == "plaintext" ]]
        then
            echo "${content}"
            break
        fi
    done 
}

read_dom () {
    local IFS=\>
    read -d \< entity content
}

#####################################################################################
### Main Script
#####################################################################################

# Process command line inputs.
OPTION_LANGUAGE=0
OPTION_INPUT_DURATION=0
LANGUAGE="en"
INPUT_DURATION="5"
HARDWARE="plughw:1,0"
for var in "$@"
do
    if [ "$var" == "-l" ] ; then
        OPTION_LANGUAGE=1
    elif [ "$var" == "-d" ] ; then
        OPTION_INPUT_DURATION=1
    elif [ $OPTION_LANGUAGE == 1 ] ; then
        OPTION_LANGUAGE=0
        LANGUAGE="$var"
    elif [ $OPTION_INPUT_DURATION == 1 ] ; then
        OPTION_INPUT_DURATION=0
        INPUT_DURATION="$var"
    else
        echo "Invalid option, valid options are -D for hardware and -d for duration"
        exit 1
    fi
done

ASSISTANT_NAME="Computer"
GREETING_TEXT="Hello, I'm listening..."
NO_ANSWER_TEXT="Sorry, I don't have an answer"
EXIT_PHRASE="bye bye"
EXIT_TEXT="OK, have a nice day"

echo `date`
echo "voice assistant running..."
echo "assistant is            : ${ASSISTANT_NAME}"
echo "language is             : ${LANGUAGE}"
echo "voice input duration is : ${INPUT_DURATION}"
echo

# Main loop
while true 
do
    echo
    voiceInput=`speechToText "$LANGUAGE" "$INPUT_DURATION" "$HARDWARE"`
    echo "> You said: ${voiceInput}"

    trimmedInput=`trim "${voiceInput}"`
    if [ "${trimmedInput}" == "" ]
    then
        echo "> ..."
    elif [ "${trimmedInput}" == "${ASSISTANT_NAME}" ]
    then
        echo "> ${ASSISTANT_NAME} said: ${GREETING_TEXT}"
        textToSpeech "$LANGUAGE" "${GREETING_TEXT}"
    elif [ "${trimmedInput}" == "${EXIT_PHRASE}" ]
    then
        echo "> ${ASSISTANT_NAME} said: ${EXIT_TEXT}."
        textToSpeech "$LANGUAGE" "${EXIT_TEXT}"
        break
    else
        response=`callWolframAlpha "${trimmedInput}"`
        if [[ "${response}" == "" ]]
        then
            echo "> ${ASSISTANT_NAME} said: ${NO_ANSWER_TEXT}."
            textToSpeech "$LANGUAGE" "${NO_ANSWER_TEXT}"
        else
            echo "> ${ASSISTANT_NAME} said: ${response}"
            textToSpeech "$LANGUAGE" "${response}"
        fi
    fi
done

echo `date`
echo "voice assistant shutdown."
exit 0 

