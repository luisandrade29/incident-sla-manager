/**
 * Creates a test user with Incident_Manager: the Incident_IT Record Type and EntitlementId are only accessible
 * with that permission set, and its holders get that Record Type as their default.
 */
@IsTest
public class IncidentTestUtil {

    public static final String MANAGER_LAST_NAME = 'IncidentMgrTest';

    // Call from @TestSetup (runAs avoids MIXED_DML_OPERATION).
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
