#!/bin/bash

#-----------------------------------------------FUNCTION PART------------------------------------------------------------------
helpFunction()
{
  echo -e "\n Require variables:                                                 Description:                       | Current values:"
  echo "---------------------------------------------------------------------------------------------------------------------------------------------------"
  echo -e "| \$JIRA_URL                       - JIRA site URL                  |  https://site.atlassian.net       |  $JIRA_URL"
  echo -e "| \$JIRA_CRED                      - JIRA cred                      |  user@mail.xyz:token              |  $JIRA_CRED"
  echo -e "| \$JIRA_REG                       - JIRA issue regexp              |  PRO-\d*                          |  $JIRA_REG"
  echo -e "| \$BUILD_RESULT                   - Build result                   |  must be SUCCESS if not fails     |  $BUILD_RESULT"
  echo -e "| \$JOB_NAME                       - Job name                       |  any                              |  $JOB_NAME"
  echo -e "| \$BUILD_DISPLAY_NAME             - Build display name             |  any                              |  $BUILD_DISPLAY_NAME"
  echo -e "| \$BUILD_URL                      - Build URL                      |  https://jenkins.site.net         |  $BUILD_URL"
  echo -e "| \$GIT_PREVIOUS_COMMIT            - Last builded commit            |  any                              |  $GIT_PREVIOUS_COMMIT"
  echo -e "| \$GIT_PREVIOUS_SUCCESSFUL_COMMIT - Last successful builded commit |  any                              |  $GIT_PREVIOUS_COMMIT"
  echo -e "| \$GIT_BRANCH                     - Current git branch             |  any                              |  $GIT_BRANCH"
  echo -e "| \$SERVICE_ENVIRONMENT            - Service environment            |  development/staging/production   |  $SERVICE_ENVIRONMENT"
  echo "-----------------------------------------------------------------------------------------------------------------------------------------------------"
  echo -e "\n Require parameters:                                                Description:                       | Current values:"
  echo "-----------------------------------------------------------------------------------------------------------------------------------------------------"
  echo -e "| -e some_env                      - Build environment             |  dev/stage/prod                   |  $BUILD_ENV"
  echo "-----------------------------------------------------------------------------------------------------------------------------------------------------"
  echo -e "\n Options:                                                           Description:                       | Current values:"
  echo "-----------------------------------------------------------------------------------------------------------------------------------------------------"
  echo -e "| -v \"some_file_name\"            - Version file                    |  by default \"version.txt\"         |  $VER_FILE"
  echo -e "| \$SERVICE_URL                    - Service URL                    |  https://some.service.net         |  $SERVICE_URL"   
  echo "-----------------------------------------------------------------------------------------------------------------------------------------------------"
  exit_code="1"
  resultFunction
}

resultFunction()
{
  if [ "$exit_code" = "1" ]
  then
    echo -e "\n--------JIRA API FINISHED WITH ERRORS----------\n"
    exit 0
  else
    echo -e "\n--------JIRA API FINISHED SUCCESSFUL----------\n"
    exit 0
  fi
}

generate_post_data()
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

#Parse each issue block
curl_function()
{
  for issue in $JIRA_ISSUE
  do
    #Cut ISSUE ID from JIRA_ISSUE block
    issue_id=`echo $issue | sed "s/_/ /g" | grep -o -P "(?<=[\h]{2})${JIRA_REG}(?=:)"`

    #Complete comment message by commit author and url
    GIT_COMMIT_AUTHOR=`echo $issue | sed "s/_/ /g" | grep -o -P "(?<=\|\#\|)[\d\w\h]+(?='$)"`
    
    GIT_COMMIT=`echo $issue | grep -o -P "[\da-z]{40}"`
    COMMIT_URL="https://github.com/`echo "${GIT_URL:15: -4}"`/commit/`echo $GIT_COMMIT`"

    #Run http request to jira ip for write comments and generate_post_data function
    echo -e "\nWrite comment to JIRA issue ID: $issue_id"
    echo "--------------------------------------"
    http_code="$(
      curl -s -o response.txt -w "%{http_code}" --request POST \
        --url "$JIRA_URL/rest/api/3/issue/$issue_id/comment" \
        --user "$JIRA_CRED" \
        --header 'Accept: application/json' \
        --header 'Content-Type: application/json' \
        --data "$(generate_post_data)"
    )"

    #Handle return codes
    if [ "$http_code" = "201" ]
    then
      echo -e "SUCCESS"
    else
      echo -e "JIRA API RETURNED ERROR CODE!"
      echo -e "HTTP response status code: $http_code"
      echo -e "Server returned:"
      cat response.txt
      exit_code="1"
    fi

    rm response.txt

  done
}

#-----------------------------------------------SCRIPT PART------------------------------------------------------------------

echo -e "\n------------------JIRA API-------------------\n"

VER_FILE="version.txt"

#Get options from console
while getopts "e:v:" opt
do
   case "$opt" in
      e ) BUILD_ENV="$OPTARG" ;;
      v ) VER_FILE="$OPTARG" ;;
      ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
   esac
done

# Print helpFunction in case parameters are empty
if [ -z "$JIRA_URL" ] || [ -z "$JIRA_CRED" ] || [ -z "$JIRA_REG" ] || [ -z "$BUILD_RESULT" ] || [ -z "$JOB_NAME" ] \
  || [ -z "$GIT_PREVIOUS_COMMIT" ] || [ -z "$BUILD_ENV" ] || [ -z "$BUILD_URL" ] \
  || [ -z "$SERVICE_ENVIRONMENT" ] || [ -z "$GIT_BRANCH" ] || [ -z "$BUILD_DISPLAY_NAME" ]
then
   echo -e "\nSome or all of the parameters are empty!";
   helpFunction
fi

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
    echo -e "Skip writing service URL...\n"
  else
    SERVICE_URL_DATA=",{\"type\":\"text\",\"text\":\": $SERVICE_URL\",\"marks\":[{\"type\":\"link\",\"attrs\":{\"href\":\"$SERVICE_URL\"}}]}"
  fi

else
  RESULT_MESSAGE=FAILED
  RESULT_EMOJI=:warning:
  RESULT_EMOJI_TEXT=:warning:
  RESULT_EMOJI_ID=atlassian-warning
fi

#If it's first build, script will be use the last commit in git
if [ "$GIT_PREVIOUS_COMMIT" = "null" ]
then
   GIT_PREVIOUS_COMMIT=`git log -1 --skip 1 --pretty=format:"%H"`
fi &&

#If it's fixed build, script will be use last successful builded commit
if [ "$FIXED_BUILD" = "1" ]
then
  GIT_PREVIOUS_COMMIT=$GIT_PREVIOUS_SUCCESSFUL_COMMIT
  RESULT_MESSAGE=FIXED
fi

# try\catch block for getting issues
{ # try
  #Get git parameters
  GIT_URL=`git config --get remote.origin.url` &&

  #Switch between issue search metod
  if [ "$BUILD_ENV" = "dev" ]
  then
    #Get issuses blocks from a git log
    JIRA_ISSUE=`git log $GIT_PREVIOUS_COMMIT..$GIT_BRANCH --pretty=format:"'%H  %s  |#|%an'" | grep -P "(?<=[\h]{2})$JIRA_REG(?=:)" | sed "s/ /_/g"`
    NO_ISSUES="No issues found from $GIT_PREVIOUS_COMMIT to last commit"
  else
    #Try to read file with version
    { # try
      VERSION=`cat $VER_FILE`
    } || { # catch
      echo -e "\n$VER_FILE not found"
      exit_code="1"
      resultFunction
    }
    #Get issuses blocks from a git log
    JIRA_ISSUE=`git log $VERSION..$GIT_BRANCH --pretty=format:"'%H  %s  |#|%an'" | grep -P "(?<=[\h]{2})$JIRA_REG(?=:)" | sed "s/ /_/g"`
    NO_ISSUES="No issues found from tag $VERSION to last commit"
  fi &&

  #Print founded issues and return message if issues not found
  if [ -z "$JIRA_ISSUE" ]
  then
    echo -e "\n$NO_ISSUES"
    exit_code="1"
    resultFunction
  else
    echo -e "Found issues: \n$JIRA_ISSUE"
    curl_function
  fi
} || { # catch
  #Return error if something wrong in try\catch block for getting issues
  echo -e "\nERROR WITH GETTING ISSUES"
  exit_code="1"
  resultFunction
}
#Finished script by result function
resultFunction