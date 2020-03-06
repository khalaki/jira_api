def call(body) {

    //Set JIRA site and regex
    env.JIRA_URL='https://xalak.atlassian.net'
    env.JIRA_REG='ABJ-\\d*'

    //Set fix build variable
    if (currentBuild?.getPreviousBuild()?.result == 'FAILURE') {
        if (currentBuild.result == 'SUCCESS') {
            env.FIXED_BUILD = "1"
        }
    }
    
    //Set build result variable
    env.BUILD_RESULT = currentBuild.result

    //Set git commit variables
    try {
        env.GIT_PREVIOUS_COMMIT = currentBuild.previousBuild.buildVariables.GIT_COMMIT
    } catch(Exception ex) {
        println("No GIT_PREVIOUS_COMMIT variable")
    }
    try {
        env.GIT_PREVIOUS_SUCCESSFUL_COMMIT = currentBuild.previousSuccessfulBuild.buildVariables.GIT_COMMIT
    } catch(Exception ex) {
        println("No GIT_PREVIOUS_SUCCESSFUL_COMMIT variable")
    }

    //Get JIRA api script
    copyArtifacts filter: 'devops/jira_api.sh', fingerprintArtifacts: true, projectName: 'jira_api', selector: lastSuccessful()

    //Set credential variable JIRA_CRED="super@user.xyz:token"
    withCredentials([string(credentialsId: 'befadc19-0d06-4214-8a46-781131b8fd98', variable: 'JIRA_CRED')]) {
        sh """
            cd devops
            chmod +x jira_api.sh
            ./jira_api.sh
        """
    archiveArtifacts 'devops/*'
    }

}
