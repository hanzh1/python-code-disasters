// Jenkins Init Script: Configure SonarQube Connection
// This script runs automatically when Jenkins starts

import jenkins.model.*
import hudson.plugins.sonar.*
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.common.*
import com.cloudbees.plugins.credentials.domains.*
import org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl
import hudson.util.Secret

// Wait for Jenkins to be ready
def instance = Jenkins.getInstance()
def maxWait = 120
def waitCount = 0
while (waitCount < maxWait) {
  try {
    if (instance.getPluginManager() != null) {
      break
    }
  } catch (Exception e) {
    Thread.sleep(1000)
    waitCount++
  }
}

// Get SonarQube token from environment
def sonarToken = System.getenv("SONARQUBE_TOKEN") ?: ""
def sonarUrl = System.getenv("SONARQUBE_URL") ?: "http://sonarqube-service.sonarqube.svc.cluster.local:9000"

if (sonarToken) {
  // Add SonarQube token credential
  def credentialsStore = Jenkins.instance.getExtensionList('com.cloudbees.plugins.credentials.SystemCredentialsProvider')[0].getStore()
  def domain = Domain.global()
  
  // Remove existing if present
  def existing = credentialsStore.getCredentials(domain).findAll { 
    it instanceof StringCredentialsImpl && it.getId() == "sonarqube-admin-token"
  }
  existing.each { cred ->
    credentialsStore.removeCredentials(domain, cred)
  }
  
  // Add new credential
  def tokenCred = new StringCredentialsImpl(
    CredentialsScope.GLOBAL,
    "sonarqube-admin-token",
    "SonarQube Admin Token",
    Secret.fromString(sonarToken)
  )
  credentialsStore.addCredentials(domain, tokenCred)
  println "✓ SonarQube token credential configured"
}

// Configure SonarQube server
try {
  def sonarConfig = SonarGlobalConfiguration.get()
  def installations = sonarConfig.getInstallations()
  def existing = installations.find { it.getName() == "SonarQube" }
  
  if (existing == null) {
    def installation = new SonarInstallation(
      "SonarQube",
      sonarUrl,
      "sonarqube-admin-token",
      null, null, null
    )
    installations.add(installation)
    sonarConfig.setInstallations(installations.toArray(new SonarInstallation[0]))
    sonarConfig.save()
    println "✓ SonarQube server configured: " + sonarUrl
  }
} catch (Exception e) {
  println "⚠ SonarQube plugin may not be installed yet: " + e.message
}

