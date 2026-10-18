// Define o supervisor dos alertas de SLA (Task, notificação e email) (registo Default de Incident_Alert_Setting__mdt) diretamente na org.
// Editar o valor localmente antes de executar e NÃO fazer commit do email real.
// Executar: sf apex run -f scripts/apex/set-supervisor-email.apex -o <org>
String supervisorEmail = 'supervisor@example.invalid';    // opcional: vazio desativa o email (canal secundário)
String supervisorUsername = 'supervisor@example.invalid'; // username do utilizador que recebe a Task e a notificação

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
System.debug('Deploy do Custom Metadata: ' + Metadata.Operations.enqueueDeployment(container, null));
