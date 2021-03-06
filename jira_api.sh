#!/bin/bash

#v0.1 beta

#1. one issue, two commits
#2. transitions
#3. other branches build

#-----------------------------------------------FUNCTION PART------------------------------------------------------------------
helpFunction()
{
  echo -e "\nRequire variables:                                                 Description:                       Current values:"
  #echo "___________________________________________________________________________________________________________________________________________________"
  echo -e "\$JIRA_URL                       - JIRA site URL                    https://site.atlassian.net         $JIRA_URL"
  echo -e "\$JIRA_CRED                      - JIRA cred                        user@mail.xyz:token                $JIRA_CRED"
  echo -e "\$JIRA_REG                       - JIRA issue regexp                PRO-\d*                            $JIRA_REG"
  echo -e "\$BUILD_RESULT                   - Build result                     must be SUCCESS if not fails       $BUILD_RESULT"
  echo -e "\$JOB_NAME                       - Job name                         any                                $JOB_NAME"
  echo -e "\$BUILD_DISPLAY_NAME             - Build display name               any                                $BUILD_DISPLAY_NAME"
  echo -e "\$BUILD_URL                      - Build URL                        https://jenkins.site.net           $BUILD_URL"
  echo -e "\$GIT_BRANCH                     - Current git branch               any                                $GIT_BRANCH"
  echo -e "\$SERVICE_ENVIRONMENT            - Service environment              development/staging/production     $SERVICE_ENVIRONMENT"

  echo -e "\nOptional variables:"
  #echo "___________________________________________________________________________________________________________________________________________________"
  echo -e "\$SERVICE_URL                    - Service URL                      https://some.service.net           $SERVICE_URL"   

  echo -e "\nOptional parameters:"
  #echo "___________________________________________________________________________________________________________________________________________________"
  echo -e "-m commit/tag                   - Issues search mode               by default: commit                  $SEARCH_MODE_SELECT"
  echo -e "-v \"some_file_name\"             - Version file                     by default: \"version.txt\"           $VER_FILE"

  exit_code="1"
  resultFunction
}

get_issues()
{
  # TRY TO GET GIT PARAMETERS
  { # try
    GIT_URL=`git config --get remote.origin.url`
    echo -e "Git found in current directory"
  } || { # catch
    echo -e "Error with getting git parameters. Script cannot find git in directory tree or remote origin URL"
    exit_code="1"
    resultFunction
  }


  # SWITCH BETWEEN ISSUES SEARCH MODE
  #Logic for commit search mode
  if [ "$SEARCH_MODE_SELECT" = "commit" ]; then
    echo -e "Selected \"by commit\" search mode"
    #If GIT_PREVIOUS_COMMIT available, use it for search issues
    if [[ "$GIT_PREVIOUS_COMMIT" =~ ^[0-9a-z]{40}$ ]]; then
      echo -e "Variable \$GIT_PREVIOUS_COMMIT is available, if build not fixed it will be used for search"
      GITLOG_FROM=$GIT_PREVIOUS_COMMIT
      #If it's fixed build, in search script will be use last successful builded commit
      if [[ "$FIXED_BUILD" = "1" ]]  && [[ "$GIT_PREVIOUS_SUCCESSFUL_COMMIT" =~ ^[0-9a-z]{40}$ ]] ;then
        echo -e "Build is fixed. The \$GIT_PREVIOUS_SUCCESSFUL_COMMIT variable will be used for search"
        GITLOG_FROM=$GIT_PREVIOUS_SUCCESSFUL_COMMIT
      fi
    #In any other causes script will be use the last commit in git
    else
      echo -e "Variable \$GIT_PREVIOUS_COMMIT is not available. Last git commit will be used for search"
      USE_GITLOG_LAST_COMMIT="true"
    fi
  #Logic for tag search mode
  elif [ "$SEARCH_MODE_SELECT" = "tag" ]; then
      echo -e "Selected \"by tag\" search mode"
      #Try to read file with version
    { # try
      GITLOG_FROM=`cat $VER_FILE`
    } || { # catch
      #Print error message if version file not tound
      echo -e "$VER_FILE not found"
      exit_code="1"
      resultFunction
    }
  else
    echo -e "\"-m $SEARCH_MODE_SELECT\" parameter is not allowed! See help"
    helpFunction
  fi


  # GETTING COMMITS FROM GIT LOG
  { #try
    if [ "$USE_GITLOG_LAST_COMMIT" = "true" ]
    then
      GITLOG_COMMIT=`git log -1 --pretty=format:"%H"`
      echo -e "Start parsing issues by commit $GITLOG_COMMIT in $GIT_BRANCH"
      JIRA_ISSUE=`git log -1 --pretty=format:"%H  %s  |#|%an|" | grep -P "(?<=[\h]{2})$JIRA_REG(?=:)" | sed "s/ /_/g"`
    else
      echo -e "Start parsing issues from $SEARCH_MODE_SELECT $GITLOG_FROM to last commit in $GIT_BRANCH branch"
      JIRA_ISSUE=`git log $GITLOG_FROM..$GIT_BRANCH --pretty=format:"%H  %s  |#|%an|" | grep -P "(?<=[\h]{2})$JIRA_REG(?=:)" | sed "s/ /_/g"`
    fi
  } || { #catch
    echo -e "Error with gettng git commits"
    exit_code="1"
    resultFunction
  }

  
  #PRINT FOUNDED ISSUES OR RETURN MESSAGE IF ISSUES NOT FOUND
  if [ -z "$JIRA_ISSUE" ]
  then
    echo -e "Issues not found!"
    resultFunction
  else
    echo -e "Found issues: \n$JIRA_ISSUE"
  fi
}

generate_static_post_data()
{
  #Completing FAILED\SUCCES message
  if [ "$BUILD_RESULT" = "SUCCESS" ]
  then
    RESULT_MESSAGE=SUCCESS
    RESULT_EMOJI=:white_check_mark:
    RESULT_EMOJI_TEXT=:white_check_mark:
    RESULT_EMOJI_ID=2705

    DEPLOY_MESSAGE="]},
      {\"type\":\"paragraph\",\"content\":[
        {\"type\":\"emoji\",\"attrs\":{\"shortName\":\":gear:\",\"id\":\"2699\",\"text\":\":gear:\"}},
        {\"type\":\"text\",\"text\":\"  Deployed to \"},
        {\"type\":\"text\",\"text\":\"$SERVICE_ENVIRONMENT\",\"marks\":[{\"type\":\"strong\"}]},
        {\"type\":\"text\",\"text\":\" environment\"}"

    #Completing service URL message
    if [ -z "$SERVICE_URL" ]
    then
      echo -e "Skip writing service URL (can be added by \$SERVICE_URL variable)"
    else
      SERVICE_URL_DATA=",{\"type\":\"text\",\"text\":\": $SERVICE_URL\",\"marks\":[{\"type\":\"link\",\"attrs\":{\"href\":\"$SERVICE_URL\"}}]}"
    fi

  else
    RESULT_MESSAGE=FAILED
    RESULT_EMOJI=:warning:
    RESULT_EMOJI_TEXT=:warning:
    RESULT_EMOJI_ID=atlassian-warning
  fi
}

#Parse each issue block
curl_function()
{
  for issue in $JIRA_ISSUE
  do
    #Cut ISSUE ID from JIRA_ISSUE block
    issue_id=`echo $issue | sed "s/_/ /g" | grep -o -P "(?<=[\h]{2})${JIRA_REG}(?=:)"`

    #Complete comment message by commit author and url
    GIT_COMMIT_AUTHOR=`echo $issue | sed "s/_/ /g" | grep -o -P "(?<=\|\#\|).*(?=\|$)"`
    
    GIT_COMMIT=`echo $issue | grep -o -P "[\da-z]{40}"`
    COMMIT_URL="https://github.com/`echo "${GIT_URL:15: -4}"`/commit/`echo $GIT_COMMIT`"

    #Run http request to jira ip for write comments and generate_post_data function
    echo -e "Write comment to JIRA issue ID: $issue_id"
    http_code="$(
      curl -s -o response.txt -w "%{http_code}" --request POST \
        --url "$JIRA_URL/rest/api/3/issue/$issue_id/comment" \
        --user "$JIRA_CRED" \
        --header 'Accept: application/json' \
        --header 'Content-Type: application/json' \
        --data "$(generate_dynamic_post_data)"
    )"

    #Handle return codes
    if [ "$http_code" = "201" ]
    then
      echo -e "SUCCESS"
      rm response.txt
    else
      echo -e "JIRA API RETURNED ERROR CODE!"
      echo -e "HTTP response status code: $http_code"
      echo -e "Server returned:"
      { 
        cat response.txt 2> /dev/null
        rm response.txt 2> /dev/null
      } || {
        echo "null"
      }
      exit_code="1"
    fi

  done
}

generate_dynamic_post_data()
{
  cat <<EOF
    {"body":{"version":1,"type":"doc","content":[
    {"type":"paragraph","content":[
      {"type":"emoji","attrs":{"shortName":"$RESULT_EMOJI","id":"$RESULT_EMOJI_ID","text":"$RESULT_EMOJI_TEXT"}},
      {"type":"text","text":" $RESULT_MESSAGE:","marks":[{"type":"strong"}]},
      {"type":"text","text":" Jenkins build - "},
      {"type":"text","text":"$JOB_NAME | $BUILD_DISPLAY_NAME","marks":[{"type":"strong"}]},
      {"type":"text","text":"  "},
      {"type":"text","text":"link","marks":[{"type":"link","attrs":{"href":"$BUILD_URL"}}]}]},
    {"type":"paragraph","content":[
      {"type":"emoji","attrs":{"shortName":":info:","id":"atlassian-info","text":":info:"}},
      {"type":"text","text":" "},
      {"type":"text","text":"Commit author:","marks":[{"type":"strong"}]},
      {"type":"text","text":"  $GIT_COMMIT_AUTHOR "},
      {"type":"inlineCard","attrs":{"url":"$COMMIT_URL"}}
      $DEPLOY_MESSAGE
      $SERVICE_URL_DATA]}]}}
EOF
}

resultFunction()
{
  if [ "$exit_code" = "1" ]
  then
    echo -e "JIRA API FINISHED WITH ERRORS"
    exit 0
  else
    echo -e "JIRA API FINISHED SUCCESSFUL"
    exit 0
  fi
}

: '

generate_post_data_transition()
{
  cat <<EOF
    {
      "transition": {
        "id": "31"
      }
    }
EOF
}
'

#-----------------------------------------------SCRIPT PART------------------------------------------------------------------

echo -e "IRA API STARTED"

#Parameters by default
VER_FILE="version.txt"
SEARCH_MODE_SELECT=commit #from last succesful builded commit

#Get options from console
while getopts "m:v:" opt
do
   case "$opt" in
      m ) SEARCH_MODE_SELECT="$OPTARG" ;;
      v ) VER_FILE="$OPTARG" ;;
      ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
   esac
done

# Print helpFunction in case parameters are empty
if [ -z "$JIRA_URL" ] || [ -z "$JIRA_CRED" ] || [ -z "$JIRA_REG" ] || [ -z "$BUILD_RESULT" ] || [ -z "$JOB_NAME" ] \
  || [ -z "$BUILD_URL" ] || [ -z "$SERVICE_ENVIRONMENT" ] || [ -z "$GIT_BRANCH" ] || [ -z "$BUILD_DISPLAY_NAME" ]
then
   echo -e "Some or all of the parameters are empty!";
   helpFunction
fi

get_issues #Get issues from commit messages

generate_static_post_data #Generate static data for issue comment

curl_function #Post comments by JIRA API

resultFunction #Finish script by result function