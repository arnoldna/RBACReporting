# RBACReporting
Azure Role Based Access Control Reporting

# Description
Gathers Azure Role Based Access Control data for audit purposes at the subscription level and outputs a CSV file.

# Use

- Download the AzureSubscriptionRBACAudit.ps1 file to your desired Windows directory.
- Open a PowerShell prompt and change to the diretory containing the AzureSubscriptionRBACAudit.ps1 file.
- Execute the following command:

    `.\AzureSubscriptionRBACAudit.ps1`

The script will prompt the user to select an Azure environment like Azure Cloud or Azure Government and will prompt the user to login utilizing their
Azure Active Directory credentials. Once logged in to Azure the script will present a list of subscriptions that the user can choose from to run the
audit against.

*NOTE:* If the user's current PowerShell session is already logged into Azure then the script will provide a list of available subscriptions in the Azure Environment
for the user to select from. Additionally, the user is only presented subscriptions that their Azure Active Directory account has access to.

The script will generate a CSV file, in the same directory as the PowerShell script, called *Subscription_Name-Azure-RBAC-Audit.csv*
