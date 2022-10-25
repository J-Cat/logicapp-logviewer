#!/bin/bash
DIALOG_CANCEL=1
DIALOG_ESC=255
HEIGHT=0
WIDTH=0
SUDO_CMD=""
REPLACEURL="https://localhost:443"
BASEURL=$(echo $ASPNETCORE_URLS | sed -E 's/\+/localhost/g')
BASEURL=${BASEURL:='http://localhost:7071'}

#check dependencies
if command -v sudo > /dev/null 2>&1; then
    SUDO_CMD="sudo"
fi
if ! command -v curl > /dev/null 2>&1; then
    read -p '"curl" is required to use this script but was not found.  Would you like to install it? [Y] ' INSTALL_CURL
    case $INSTALL_CURL in
    Y|y)
        $SUDO_CMD apt-get install curl -y
        ;;
    *)
        exit 1;
        ;;
    esac
fi
if ! command -v dialog > /dev/null 2>&1; then
    read -p '"dialog" is required to use this script but was not found.  Would you like to install it? [Y] ' INSTALL_DIALOG
    case $INSTALL_DIALOG in
    Y|y)
        $SUDO_CMD apt-get install dialog -y
        ;;
    *)
        exit 1;
        ;;
    esac
fi
if ! command -v jq > /dev/null 2>&1; then
    read -p '"jq" is required to use this script but was not found.  Would you like to install it? [Y] ' INSTALL_JQ
    case $INSTALL_JQ in
    Y|y)
        $SUDO_CMD curl "https://objects.githubusercontent.com/github-production-release-asset-2e65be/5101141/6387d980-de1f-11e8-8d3e-4455415aa408?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIWNJYAX4CSVEH53A%2F20221022%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20221022T045948Z&X-Amz-Expires=300&X-Amz-Signature=eaa2960d78083d54888085534d3833f808f84de718d73224351684bbd80934da&X-Amz-SignedHeaders=host&actor_id=22578964&key_id=0&repo_id=5101141&response-content-disposition=attachment%3B%20filename%3Djq-linux64&response-content-type=application%2Foctet-stream" -o /usr/bin/jq
        $SUDO_CMD chmod a+x /usr/bin/jq
        ;;
    *)
        exit 1;
        ;;
    esac
fi
if ! command -v less > /dev/null 2>&1; then
    read -p '"less" is required to use this script but was not found.  Would you like to install it? [Y] ' INSTALL_LESS
    case $INSTALL_LESS in
    Y|y)
        $SUDO_CMD apt-get install less -y
        ;;
    *)
        exit 1;
        ;;
    esac
fi

# get API code and list of workflows
if [ "$APICODE" != "" ]; then
    echo "APICODE already set.  Not retrieving."
elif [ "${AzureWebJobsSecretStorageType,,}" == "kubernetes" ]; then
    POD_NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
    KUBE_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
    APICODE=$(curl -sSk -H "Authorization: Bearer $KUBE_TOKEN" "https://kubernetes.default:443/api/v1/namespaces/$POD_NAMESPACE/$AzureWebJobsKubernetesSecretName" | jq -cr .data.\"host.master\" | base64 --decode)
elif [ "${AzureWebJobsSecretStorageType,,}" == "files" ]; then
    KEYS_FILES=($(ls -b -t -d ~/.aspnet/DataProtection-Keys/*))
    APICODE=$(cat ${KEYS_FILES[0]} | grep "<value>" | sed -E 's/^ *<value>([^\<]*)<\/value>.*$/\1/g')
else
    APICODE=$(curl -H 'Content-Type: application/json' -s "$BASEURL/admin/host/keys/default" | jq -r .value)
fi

WORKFLOWS=($(curl -s "$BASEURL/runtime/webhooks/workflow/api/management/workflows?code=$APICODE" | jq -r '.|sort_by(.name)|.[]|.name'))

workflowActionRepetitionMenu() {
    clear

    REPETITION_PROPERTIES=$(curl -s "$BASEURL/runtime/webhooks/workflow/api/management/workflows/$1/runs/$2/actions/$3/repetitions/$4?code=$APICODE")
    REPETITION_INPUTURL=$(echo "$REPETITION_PROPERTIES" | jq -r .properties.inputsLink.uri | sed 's@'"$REPLACEURL"'@'"$BASEURL"'@')
    REPETITION_OUTPUTURL=$(echo "$REPETITION_PROPERTIES" | jq -r .properties.outputsLink.uri | sed 's@'"$REPLACEURL"'@'"$BASEURL"'@')
    REPETITION_MENU_ITEMS=("P" "Properties")
    REPETITION_ACTION_COUNT=1
    if [ "$REPETITION_INPUTURL" != "null" ]; then
        REPETITION_MENU_ITEMS+=("I" "Action_Input")
        REPETITION_ACTION_COUNT=$(($REPETITION_ACTION_COUNT + 1))
    fi
    if [ "$REPETITION_OUTPUTURL" != "null" ]; then
        REPETITION_MENU_ITEMS+=("O" "Action_Output")
        REPETITION_ACTION_COUNT=$(($REPETITION_ACTION_COUNT + 1))
    fi
    while true; do
        exec 3>&1
        REPETITION_MENU_ID=$(dialog --backtitle "Logic App Workflow Log Viewer" --menu "$2 - Repetition $3" $HEIGHT $WIDTH $REPETITION_ACTION_COUNT ${REPETITION_MENU_ITEMS[@]} 2>&1 1>&3)
        exit_status=$?
        exec 3>&-

        case $exit_status in
        $DIALOG_CANCEL | $DIALOG_ESC)
            clear
            return
            ;;
        esac

        case $REPETITION_MENU_ID in
        P)
            echo "$REPETITION_PROPERTIES" | jq -C . | less -R
            ;;
        I)
            curl -s $REPETITION_INPUTURL | jq -C . | less -R
            ;;
        O)
            curl -s $REPETITION_OUTPUTURL | jq -C . | less -R
            ;;
        esac
    done
}

workflowActionRepetitionsMenu() {
    clear
    while true; do
        exec 3>&1
        REPETITIONS_MENU_ID=$(dialog --backtitle "Logic App Workflow Log Viewer" --column-separator "|" --menu "$3 - Repetitions" $HEIGHT $WIDTH $(((${#ACTION_REPETITIONS[@]} + 1) / 2)) ${ACTION_REPETITIONS[@]} 2>&1 1>&3)
        exit_status=$?
        exec 3>&-

        case $exit_status in
        $DIALOG_CANCEL | $DIALOG_ESC)
            clear
            return
            ;;
        esac

        workflowActionRepetitionMenu $1 $2 $3 $REPETITIONS_MENU_ID
    done
}

workflowRunActionMenu() {
    clear
    ACTION_PROPERTIES=$(curl -s "$BASEURL/runtime/webhooks/workflow/api/management/workflows/$1/runs/$2/actions/$3?code=$APICODE")
    ACTION_REPETITIONS=($(curl -s "$BASEURL/runtime/webhooks/workflow/api/management/workflows/$1/runs/$2/actions/$3/repetitions?code=$APICODE" | jq -r '.value[]|.name,([(.properties.startTime|sub("(?<d>[^\\.]+).*$";"\(.d)Z")|fromdate|strflocaltime("%I:%M:%S%P")),.properties.status]|join("|"))' 2> /dev/null))
    ACTION_INPUTURL=$(echo "$ACTION_PROPERTIES" | jq -r .properties.inputsLink.uri | sed 's@'"$REPLACEURL"'@'"$BASEURL"'@')
    ACTION_OUTPUTURL=$(echo "$ACTION_PROPERTIES" | jq -r .properties.outputsLink.uri | sed 's@'"$REPLACEURL"'@'"$BASEURL"'@')
    ACTION_MENU_ITEMS=("P" "Properties")
    ACTION_COUNT=1
    if [ "$ACTION_INPUTURL" != "null" ]; then
        ACTION_MENU_ITEMS+=("I" "Action_Input")
        ACTION_COUNT=$(($ACTION_COUNT + 1))
    fi
    if [ "$ACTION_OUTPUTURL" != "null" ]; then
        ACTION_MENU_ITEMS+=("O" "Action_Output")
        ACTION_COUNT=$(($ACTION_COUNT + 1))
    fi
    if [ "$ACTION_REPETITIONS" != "" ]; then
        ACTION_MENU_ITEMS+=("R" "Repetitions")
        ACTION_COUNT=$(($ACTION_COUNT + 1))
    fi
    while true; do
        exec 3>&1
        ACTION_MENU_ID=$(dialog --backtitle "Logic App Workflow Log Viewer" --column-separator "|" --menu "Actions ($2)" $HEIGHT $WIDTH $ACTION_COUNT ${ACTION_MENU_ITEMS[@]} 2>&1 1>&3)
        exit_status=$?
        exec 3>&-

        case $exit_status in
        $DIALOG_CANCEL | $DIALOG_ESC)
            clear
            return
            ;;
        esac

        case $ACTION_MENU_ID in
        P)
            echo "$ACTION_PROPERTIES" | jq -C . | less -R
            ;;
        I)
            curl -s $ACTION_INPUTURL | jq -C . | less -R
            ;;
        O)
            curl -s $ACTION_OUTPUTURL | jq -C . | less -R
            ;;
        R)
            workflowActionRepetitionsMenu $1 $2 $3
        esac
    done
}

workflowRunActionsMenu() {
    clear
    RUN_ACTIONS=($(curl -s "$BASEURL/runtime/webhooks/workflow/api/management/workflows/$1/runs/$2/actions?code=$APICODE" | jq -r '.value|sort_by(.properties.startTime)|.[]|.name,([(.properties.startTime|sub("(?<d>[^\\.]+).*$";"\(.d)Z")|fromdate|strflocaltime("%I:%M:%S%P")),.properties.status]|join("|"))'))

    if [ ${#RUN_ACTIONS[@]} == 0 ]; then
        dialog --timeout 2 --backtitle "Logic App Workflow Log Viewer" --msgbox "No run actions found for the selected workflow run." 0 0
        return
    fi

    while true; do
        exec 3>&1
        ACTION_NAME=$(dialog --backtitle "Logic App Workflow Log Viewer"  --column-separator "|" --menu "Actions ($2)" $HEIGHT $WIDTH $(((${#RUN_ACTIONS[@]} + 1) / 2)) ${RUN_ACTIONS[@]} 2>&1 1>&3)
        exit_status=$?
        exec 3>&-

        case $exit_status in
        $DIALOG_CANCEL | $DIALOG_ESC)
            clear
            return
            ;;
        esac

        workflowRunActionMenu $1 $2 $ACTION_NAME
    done
}

workflowRunMenu() {
    clear
    RUN_MENU_OPTIONS=("P" "Properties/JSON")

    WFPROPERTIES=$(curl -s "$BASEURL/runtime/webhooks/workflow/api/management/workflows/$1/runs/$2?code=$APICODE")
    WFINPUTURL=$(echo "$WFPROPERTIES" | jq -r .properties.trigger.inputsLink.uri | sed 's@'"$REPLACEURL"'@'"$BASEURL"'@')
    WFOUTPUTURL=$(echo "$WFPROPERTIES" | jq -r .properties.trigger.outputsLink.uri | sed 's@'"$REPLACEURL"'@'"$BASEURL"'@')
    WFRESPONSEURL=$(echo "$WFPROPERTIES" | jq -r .properties.response.outputsLink.uri | sed 's@'"$REPLACEURL"'@'"$BASEURL"'@')

    WFCOUNT=3
    if [ "$WFINPUTURL" != "null" ]; then
        RUN_MENU_OPTIONS+=("I" "Trigger_Input")
        WFCOUNT=$(($WFCOUNT + 1))
    fi
    if [ "$WFOUTPUTURL" != "null" ]; then
        RUN_MENU_OPTIONS+=("O" "Trigger_Output")
        WFCOUNT=$(($WFCOUNT + 1))
    fi
    if [ "$WFRESPONSEURL" != "null" ]; then
        RUN_MENU_OPTIONS+=("R" "Response")
        WFCOUNT=$(($WFCOUNT + 1))
    fi
    RUN_MENU_OPTIONS+=("A" "Actions")
    RUN_MENU_OPTIONS+=("C" "Cancel_Run")

    while true; do
        exec 3>&1
        RUN_MENU_ACTION=$(dialog --backtitle "Logic App Workflow Log Viewer" --menu "Run $2" $HEIGHT $WIDTH $WFCOUNT ${RUN_MENU_OPTIONS[@]} 2>&1 1>&3)
        exit_status=$?
        exec 3>&-

        case $exit_status in
        $DIALOG_CANCEL | $DIALOG_ESC)
            clear
            return
            ;;
        esac

        case $RUN_MENU_ACTION in
        P)
            echo "$WFPROPERTIES" | jq -C . | less -R
            ;;
        I)
            curl -s $WFINPUTURL | jq -C . | less -R
            ;;
        O)
            curl -s $WFOUTPUTURL | jq -C . | less -R
            ;;
        R)
            curl -s $WFRESPONSEURL | jq -C . | less -R
            ;;
        A)
            workflowRunActionsMenu $1 $2
            ;;
        C)
            echo $(curl -H "Content-Type: application/json" -d "" -s "$BASEURL/runtime/webhooks/workflow/api/management/workflows/$1/runs/$2/cancel?code=$APICODE") | jq -C . | less -R
            ;;
        esac
    done
}

workflowMenu() {
    clear

    WORKFLOW_RUNS=($(curl -s "$BASEURL/runtime/webhooks/workflow/api/management/workflows/${WORKFLOWS[($1 - 1)]}/runs?code=$APICODE" |  jq -r '.value|sort_by(.properties.startTime)|reverse|.[]|.name,([(.properties.startTime|sub("(?<d>[^\\.]+).*$";"\(.d)Z")|fromdate|strflocaltime("%Y-%m-%d_%I:%M%P")),.properties.status]|join("|"))'))
    WORKFLOW_PROPERTIES=$(curl -s "$BASEURL/runtime/webhooks/workflow/api/management/workflows/${WORKFLOWS[($1 - 1)]}?code=$APICODE")
    WORKFLOW_TRIGGER_TYPE="$(echo $WORKFLOW_PROPERTIES | jq -r '.triggers|first(.[])|.type')"
    WORKFLOW_TRIGGER_NAME="$(echo $WORKFLOW_PROPERTIES | jq -r '.triggers|keys|first(.[])')"
    CALLBACK_URI=""
    CALLBACK_JSON=""
    CALLBACK_METHOD="POST"
    case $WORKFLOW_TRIGGER_TYPE in
    Recurrence)
        CALLBACK_URI="$BASEURL/runtime/webhooks/workflow/api/management/workflows/${WORKFLOWS[($1 - 1)]}/triggers/$WORKFLOW_TRIGGER_NAME/run?code=$APICODE"
        ;;
    Request)
        clear
        CALLBACK_PROPERTIES=$(curl -H "Content-Type: application/json" -d "" -s "$BASEURL/runtime/webhooks/workflow/api/management/workflows/${WORKFLOWS[($1 - 1)]}/triggers/$WORKFLOW_TRIGGER_NAME/listCallbackUrl?code=$APICODE")
        CALLBACK_URI=$(echo $CALLBACK_PROPERTIES | jq -r .value | sed 's@'"$REPLACEURL"'@'"$BASEURL"'@')
        CALLBACK_METHOD=$(echo $CALLBACK_PROPERTIES | jq -r .method)
        CALLBACK_JSON=$(curl -s "$BASEURL/runtime/webhooks/workflow/api/management/workflows/${WORKFLOWS[($1 - 1)]}/triggers/manual/schemas/json?code=$APICODE")
        ;;
    esac

    WORKFLOW_MENU_BASE_COUNT=1
    WORKFLOW_MENU_ITEMS=("P" "Properties")
    if [ "$CALLBACK_URI" != "" ]; then
        WORKFLOW_MENU_BASE_COUNT=2
        WORKFLOW_MENU_ITEMS+=("R" "Run_Workflow")
    fi

    WORKFLOW_MENU_COUNT=$WORKFLOW_MENU_BASE_COUNT
    if [ ${#WORKFLOW_RUNS[@]} -gt 0 ]; then
        WORKFLOW_MENU_COUNT=$(($WORKFLOW_MENU_COUNT + ((${#WORKFLOW_RUNS[@]} + 1) / 2)))
    fi

    while true; do
        clear
        exec 3>&1
        RUNID=$(dialog --backtitle "Logic App Workflow Log Viewer" --column-separator "|" --menu "${WORKFLOWS[($1 - 1)]}" $HEIGHT $WIDTH $WORKFLOW_MENU_COUNT ${WORKFLOW_MENU_ITEMS[@]} ${WORKFLOW_RUNS[@]} 2>&1 1>&3)
        exit_status=$?
        exec 3>&-
        case $exit_status in
        $DIALOG_CANCEL | $DIALOG_ESC)
            clear
            return
            ;;
        esac

        case $RUNID in
        P)
            clear
            echo $WORKFLOW_PROPERTIES | jq -C . | less -R
            ;;
        R)
            RUN_WORKFLOW=0
            exec 3>&1
            JSONBODY=""
            if [ "$WORKFLOW_TRIGGER_TYPE" == "Request" ] && [ "$CALLBACK_METHOD" == "POST" ]; then
                JSONBODY=$(dialog --backtitle "Logic App Workflow Log Viewer" --inputbox "Body to Post" 0 0 "$CALLBACK_JSON" 2>&1 1>&3)
                exit_status=$?
                exec 3>&-
                if [ $exit_status != $DIALOG_CANCEL ] && [ $exit_status != $DIALOG_ESC ]; then
                    RUN_WORKFLOW=1
                fi
            else
                RUN_WORKFLOW=1
            fi
            if [ $RUN_WORKFLOW == 1 ]; then
                clear
                echo "Running workflow ..."
                if [ "$CALLBACK_METHOD" == "POST" ]; then
                    curl -H "Content-Type: application/json" -d "$JSONBODY" -s "$CALLBACK_URI"
                else
                    curl -H "Content-Type: application/json" -s "$CALLBACK_URI"
                fi
                read -p "Press <enter> to continue."
                WORKFLOW_RUNS=($(curl -s "$BASEURL/runtime/webhooks/workflow/api/management/workflows/${WORKFLOWS[($1 - 1)]}/runs?code=$APICODE" |  jq -r '.value|sort_by(.properties.startTime)|reverse|.[]|.name,([(.properties.startTime|sub("(?<d>[^\\.]+).*$";"\(.d)Z")|fromdate|strflocaltime("%Y-%m-%d_%I:%M%P")),.properties.status]|join("|"))'))
                if [ ${#WORKFLOW_RUNS[@]} -gt 0 ]; then
                    WORKFLOW_MENU_COUNT=$(($WORKFLOW_MENU_BASE_COUNT + ((${#WORKFLOW_RUNS[@]} + 1) / 2)))
                fi
            fi
            ;;
        *)
            workflowRunMenu ${WORKFLOWS[($1 - 1)]} $RUNID
            ;;
        esac
    done
}

# main menu
while true; do
    exec 3>&1
    selection=$(dialog --cancel-label "Exit" --backtitle "Logic App Workflow Log Viewer" --menu "Workflows" $HEIGHT $WIDTH ${#WORKFLOWS[@]} $( (for ((i = 0; i < ${#WORKFLOWS[@]}; i++)); do echo -n "$(($i + 1)) ${WORKFLOWS[$i]} "; done)) 2>&1 1>&3)
    exit_status=$?
    exec 3>&-

    case $exit_status in
    $DIALOG_CANCEL)
        clear
        echo "Program terminated."
        exit
        ;;
    $DIALOG_ESC)
        clear
        echo "Program aborted." >&2
        exit 1
        ;;
    esac

    workflowMenu $selection
done
