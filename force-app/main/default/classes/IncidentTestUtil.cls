/**
 * Utilitário de testes: cria um utilizador com o Permission Set Incident_Manager.
 * Necessário porque o Record Type "Incidente de TI" e o campo EntitlementId só ficam acessíveis com esse Permission Set,
 * e quem o tem passa a ter esse Record Type como predefinido.
 */
@IsTest
public class IncidentTestUtil {

    public static final String MANAGER_LAST_NAME = 'IncidentMgrTest';

    // Chamar a partir de @TestSetup (usa runAs para evitar MIXED_DML_OPERATION).
    public static void createManager() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            User u = new User(
                Alias = 'incmgr', Email = 'incmgr@example.invalid', EmailEncodingKey = 'UTF-8', LastName = MANAGER_LAST_NAME,
                LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US', TimeZoneSidKey = 'Europe/Lisbon',
                ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
                Username = 'incmgr' + System.currentTimeMillis() + '@example.invalid'
            );
            insert u;
            insert new PermissionSetAssignment(
                AssigneeId = u.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Incident_Manager' LIMIT 1].Id
            );
        }
    }

    public static User getManager() {
        return [SELECT Id FROM User WHERE LastName = :MANAGER_LAST_NAME LIMIT 1];
    }

    public static Id incidentRecordTypeId() {
        return Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('Incident_IT').getRecordTypeId();
    }
}
