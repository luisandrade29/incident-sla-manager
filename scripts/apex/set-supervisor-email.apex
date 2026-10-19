// Sets the SLA alert supervisor (Default record of Incident_Alert_Setting__mdt) directly in the org.
// Edit the values locally before running and NEVER commit a real address.
// Executar: sf apex run -f scripts/apex/set-supervisor-email.apex -o <org>
String supervisorEmail = 'supervisor@example.invalid';    // optional: empty disables the email (secondary channel)
String supervisorUsername = 'supervisor@example.invalid'; // username of the user who receives the Task and bell notification

Metadata.CustomMetadata record = new Metadata.CustomMetadata();
record.fullName = 'Incident_Alert_Setting.Default';
record.label = 'Default';
Metadata.CustomMetadataValue value = new Metadata.CustomMetadataValue();
value.field = 'Supervisor_Email__c';
value.value = supervisorEmail;
record.values.add(value);
Metadata.CustomMetadataValue userValue = new Metadata.CustomMetadataValue();
userValue.field = 'Supervisor_Username__c';
userValue.value = supervisorUsername;
record.values.add(userValue);

Metadata.DeployContainer container = new Metadata.DeployContainer();
container.addMetadata(record);
System.debug('Custom Metadata deploy: ' + Metadata.Operations.enqueueDeployment(container, null));
