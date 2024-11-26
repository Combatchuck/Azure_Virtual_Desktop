# Azure_Virtual_Desktop
### Automations I created to help manage AVD


## High level is that runbooks call template specs. 

If you find it hard to edit the template spec (since you can't add variables to the format). 
- Create a deployment to add hosts to a pool
- When on the create page, select download as template
- Chose a place to store the template spec
- Use my format to set predefined "default variables" so that they are needing to be passed via the runbook automation

## You should only need to edit the variables block for all the runbooks
