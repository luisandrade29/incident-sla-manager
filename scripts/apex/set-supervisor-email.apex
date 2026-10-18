// Define o destinatário dos alertas de SLA (registo Default de Incident_Alert_Setting__mdt) diretamente na org.
// Editar o valor localmente antes de executar e NÃO fazer commit do email real.
// Executar: sf apex run -f scripts/apex/set-supervisor-email.apex -o <org>
String supervisorEmail = 'supervisor@example.invalid';

Metadata.CustomMetadata record = new Metadata.CustomMetadata();
record.fullName = 'Incident_Alert_Setting.Default';
record.label = 'Default';
Metadata.CustomMetadataValue value = new Metadata.CustomMetadataValue();
value.field = 'Supervisor_Email__c';
value.value = supervisorEmail;
record.values.add(value);

Metadata.DeployContainer container = new Metadata.DeployContainer();
container.addMetadata(record);
System.debug('Deploy do Custom Metadata: ' + Metadata.Operations.enqueueDeployment(container, null));
