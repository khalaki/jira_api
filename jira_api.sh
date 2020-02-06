#!/bin/bash

echo -e "\n------------------JIRA API-------------------\n"

VER_FILE="version.txt"

helpFunction()
{
  echo -e "\n| Require variables:                                                              | Current values:"
  echo "-------------------------------------------------------------------------------------------------------------------"
  echo -e "| \$JIRA_URL             - JIRA site URL       |  https://site.atlassian.net       |  $JIRA_URL"
  echo -e "| \$JIRA_CRED            - JIRA cred           |  user@mail.xyz:token              |  $JIRA_CRED"
  echo -e "| \$JIRA_REG             - JIRA issue regexp   |  PRO-\d*                          |  $JIRA_REG"
  echo -e "| \$BUILD_RESULT         - Build result        |  must be SUCCESS if not fails     |  $BUILD_RESULT"
  echo -e "| \$BUILD_DISPLAY_NAME   - Build name          |  any                              |  $BUILD_DISPLAY_NAME"
  echo -e "| \$GIT_PREVIOUS_COMMIT  - Last builded commit |  any                              |  $GIT_PREVIOUS_COMMIT"  
  echo "-------------------------------------------------------------------------------------------------------------------"
  echo -e "\n| Require parameters:                                                             | Current values:"
  echo "-------------------------------------------------------------------------------------------------------------------"
  echo -e "| -e some_env           - Build environment   |  dev/stage/prod                   |  $BUILD_ENV"
  echo "-------------------------------------------------------------------------------------------------------------------"
  echo -e "\n| Options:                                                                        | Current values:"
  echo "-------------------------------------------------------------------------------------------------------------------"
  echo -e "| -v \"some_file_name\"   - Version file        |  by default \"version.txt\"         |  $VER_FILE"
  echo "-------------------------------------------------------------------------------------------------------------------"
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
    {"type":"text","text":" Jenkins build "},
    {"type":"text","text":"$BUILD_DISPLAY_NAME","marks":[{"type":"em"}]},
    {"type":"text","text":"  "},
    {"type":"text","text":"link","marks":[{"type":"link","attrs":{"href":"$BUILD_URL"}}]}]},
    {"type":"paragraph","content":[
    {"type":"emoji","attrs":{"shortName":":info:","id":"atlassian-info","text":":info:"}},
    {"type":"text","text":" "},
    {"type":"text","text":"Commit author:","marks":[{"type":"strong"}]},
    {"type":"text","text":"  $GIT_COMMIT_AUTHOR "},{"type":"inlineCard","attrs":{"url":"$COMMIT_URL"}}]}]}}
EOF
}

curl_function()
{
  for issue in $JIRA_ISSUE
  do
    issue_id=`echo $issue | grep -o -P "$JIRA_REG"`

    if [[ ${issue_id} =~ ${JIRA_REG} ]]
    then
      GIT_COMMIT_AUTHOR=`echo $issue | grep -o -P "^[\s\dA-z]*"`
      GIT_COMMIT=`echo $issue | grep -o -P "[\da-z]{40}"`
      COMMIT_URL="https://github.com/`echo "${GIT_URL:15: -4}"`/commit/`echo $GIT_COMMIT`"

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

      if [ "$http_code" = "201" ]
      then
        echo -e "SUCCESS"
      else
        echo -e "JIRA API RETURNED ERROR CODE!"
        echo -e "HTTP response status code: $http_code"
        echo -e "Server returned:"
        cat response.txt | jq
        exit_code="1"
      fi
    fi
  done

  rm response.txt
}

while getopts "e:v:" opt
do
   case "$opt" in
      e ) BUILD_ENV="$OPTARG" ;;
      v ) VER_FILE="$OPTARG" ;;
      ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
   esac
done

# Print helpFunction in case parameters are empty
if [ -z "$JIRA_URL" ] || [ -z "$JIRA_CRED" ] || [ -z "$JIRA_REG" ] || [ -z "$BUILD_RESULT" ] || [ -z "$BUILD_DISPLAY_NAME" ] \
  || [ -z "$GIT_PREVIOUS_COMMIT" ] || [ -z "$BUILD_ENV" ]
then
   echo -e "\nSome or all of the parameters are empty!";
   helpFunction
fi

if [ "$BUILD_RESULT" = "SUCCESS" ]
then
  RESULT_MESSAGE=SUCCESS
  RESULT_EMOJI=:white_check_mark:
  RESULT_EMOJI_TEXT=:white_check_mark:
  RESULT_EMOJI_ID=2705
else
  RESULT_MESSAGE=FAILED
  RESULT_EMOJI=:warning:
  RESULT_EMOJI_TEXT=:warning:
  RESULT_EMOJI_ID=atlassian-warning
fi

{ # try
  GIT_URL=`git config --get remote.origin.url` &&
  GIT_BRANCH=`git rev-parse --abbrev-ref HEAD` &&

  if [ "$BUILD_ENV" = "dev" ]
  then
    JIRA_ISSUE=`git log $GIT_PREVIOUS_COMMIT..$GIT_BRANCH --pretty=format:"%an|-|%H|-|%s" | grep -o -P "^[\S]*-.$JIRA_REG"`
    NO_ISSUES="No issues found from $GIT_PREVIOUS_COMMIT to last commit"
  else
    { # try
      VERSION=`cat $VER_FILE`
    } || { # catch
      echo -e "\n$VER_FILE not found"
      exit_code="1"
      resultFunction
    }
    JIRA_ISSUE=`git log $VERSION..$GIT_BRANCH --pretty=format:"%an|-|%H|-|%s" | grep -o -P "^[\S]*-.$JIRA_REG"`
    NO_ISSUES="No issues found from tag $VERSION to last commit"
  fi &&

  if [ -z "$JIRA_ISSUE" ]
  then
    echo -e "\n$NO_ISSUES"
  else
    echo -e "Found issues: \n$JIRA_ISSUE"
    curl_function
  fi
} || { # catch
  echo -e "\ngit repository not found"
  exit_code="1"
  resultFunction
}

resultFunction